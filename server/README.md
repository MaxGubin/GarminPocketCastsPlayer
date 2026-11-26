# Podcast speed service (Google Cloud Run)

Speeds up podcast episodes for the Podcast Sync watch app, which can't change
the playback rate itself. The watch downloads
`/audio?url=<episode URL>&speed=1.5` instead of the original file; the
service converts it with ffmpeg (`atempo`, pitch preserved, mono MP3) and
redirects the watch to the converted file in Cloud Storage.

Your Pocket Casts login never reaches this service; it only sees public
episode audio URLs.

## Create a Google Cloud project

One-time setup. Billing must be enabled even if usage stays within the free
tier.

### 1. Install the gcloud CLI and sign in

```bash
# Ubuntu (snap); other systems: https://cloud.google.com/sdk/docs/install
sudo snap install google-cloud-cli --classic

gcloud auth login            # opens a browser to sign in with your Google account
```

### 2. Create a billing account (if you don't have one)

This needs a payment method, so it's done in the web console:
<https://console.cloud.google.com/billing> → **Create account**. New accounts
often come with free trial credit.

### 3. Create the project and link billing

The project ID must be globally unique: 6–30 characters, lowercase letters,
digits and hyphens, starting with a letter. It can't be changed later.

```bash
PROJECT=podcast-speed-$RANDOM          # or pick your own ID
gcloud projects create $PROJECT --name="Podcast speed"
gcloud config set project $PROJECT

gcloud billing accounts list           # copy the ACCOUNT_ID (XXXXXX-XXXXXX-XXXXXX)
BILLING=XXXXXX-XXXXXX-XXXXXX
gcloud billing projects link $PROJECT --billing-account=$BILLING
```

### 4. Optional: budget alert

Sends email when spending reaches 50 %, 90 % and 100 % of the amount. It only
alerts; it doesn't stop the service.

```bash
gcloud services enable billingbudgets.googleapis.com
gcloud billing budgets create --billing-account=$BILLING \
    --display-name="Podcast speed" --budget-amount=5USD \
    --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 \
    --threshold-rule=percent=1.0
```

Alternatively, all of this can be done in the console:
<https://console.cloud.google.com/projectcreate>, then **Billing** →
**Link a billing account**, and **Billing** → **Budgets & alerts**.

## Deploy

Needs the gcloud CLI and the project from the previous section. If you're
continuing in the same shell, `PROJECT` is already set; otherwise set it to
your project ID below.

```bash
PROJECT=${PROJECT:-your-project-id}   # keeps the ID from the previous section
REGION=europe-west1                 # any Cloud Run region near you
BUCKET=$PROJECT-podcast-speed       # must be globally unique
SA=podcast-speed@$PROJECT.iam.gserviceaccount.com

gcloud config set project $PROJECT
gcloud services enable run.googleapis.com cloudbuild.googleapis.com \
    artifactregistry.googleapis.com iamcredentials.googleapis.com

# Service account the service runs as
gcloud iam service-accounts create podcast-speed
# ...allowed to read/write the cache bucket
gcloud storage buckets create gs://$BUCKET --location=$REGION --uniform-bucket-level-access
gcloud storage buckets add-iam-policy-binding gs://$BUCKET \
    --member=serviceAccount:$SA --role=roles/storage.objectAdmin
# ...and to sign download URLs as itself
gcloud iam service-accounts add-iam-policy-binding $SA \
    --member=serviceAccount:$SA --role=roles/iam.serviceAccountTokenCreator
# Delete converted files after 7 days
gcloud storage buckets update gs://$BUCKET --lifecycle-file=lifecycle.json

# Shared secret; enter the same value in the watch app settings
API_KEY=$(openssl rand -hex 24); echo "API key: $API_KEY"

# Run from this folder (server/), which has the Dockerfile. From the repo
# root, Cloud Build finds no Dockerfile, tries Python buildpacks and fails
# with "provide a main.py or app.py file".
gcloud run deploy podcast-speed --source . --region $REGION \
    --service-account $SA \
    --allow-unauthenticated \
    --set-env-vars API_KEY=$API_KEY,CACHE_BUCKET=$BUCKET \
    --cpu 2 --memory 2Gi --timeout 900 --concurrency 8 \
    --min-instances 0 --max-instances 1 --cpu-boost --no-cpu-throttling
```

`--max-instances 1` keeps all requests on one instance, so that a request
for an episode that is already being converted (a watch retry, or the
background conversion of `next`) waits for that conversion instead of
starting a second one. One instance with 2 vCPUs converts two episodes at
once.

`--no-cpu-throttling` keeps the CPU available between requests, which the
background conversion of the next episode needs. Cloud Run then bills the
instance for as long as it runs (it shuts down about 15 minutes after the
last request), still within the free tier for a daily sync.

`--allow-unauthenticated` is needed because the watch can't send Google
credentials; the `API_KEY` check protects the service instead.

The deploy prints the service URL (`https://podcast-speed-....run.app`).

## Test

```bash
URL=https://podcast-speed-....run.app
EP='https://example.com/episode.mp3'   # any episode audio URL
curl -sSL -o fast.mp3 -w '%{http_code} %{size_download} bytes %{time_total}s\n' \
    -H "X-Api-Key: $API_KEY" \
    --get --data-urlencode "url=$EP" --data speed=1.5 "$URL/audio"
```

The second request for the same episode and speed is a cache hit and returns
in about a second.

## Run locally (without Cloud Storage)

```bash
docker build -t podcast-speed .
docker run --rm -p 8080:8080 -e API_KEY=test podcast-speed
curl -sS -o fast.mp3 -H 'X-Api-Key: test' --get \
    --data-urlencode "url=$EP" --data speed=1.5 http://localhost:8080/audio
```

## API

`GET /audio`

| Parameter | | |
|---|---|---|
| `url` | required | Original episode audio URL (http/https) |
| `speed` | default 1.0 | 0.5 to 3.0 |
| `kbps` | default 64 | MP3 bitrate, 32 to 128 (mono) |
| `next` | optional | URL of the next episode, converted ahead in the background |
| `key` | | API key, if not sent as the `X-Api-Key` header |

Responses: `302` to the converted file (with `CACHE_BUCKET`), or the MP3
itself (without it); `400` bad parameters; `401` wrong key; `502` the episode
couldn't be downloaded or converted.

`next` (optional) is the URL of the episode the watch will request after this
one. The service converts it in the background while the watch downloads the
current file, so the next request is answered from the cache. That halves the
sync time, roughly: without it the watch waits for ffmpeg (about 30 s for an
hour-long episode) before every download.

## Cost

With `--min-instances 0` nothing runs between syncs. A few dozen conversions a
month (about 30 s of 2 vCPUs each) fit in the Cloud Run free tier; storage of a
week of converted episodes costs a few cents a month.

ARG ELASTIC_VERSION

# https://www.docker.elastic.co/
FROM docker.elastic.co/elasticsearch/elasticsearch-wolfi:${ELASTIC_VERSION:-9.3.1}

# Add your elasticsearch plugins setup here
# Plugin for S3/MinIO snapshots support
RUN bin/elasticsearch-plugin install --batch repository-s3
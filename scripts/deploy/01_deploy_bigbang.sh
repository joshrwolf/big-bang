#!/usr/bin/env bash

set -ex

CI_VALUES_FILE="tests/ci/k3d/values.yaml"

if [[ "${CI_COMMIT_BRANCH}" == "${CI_DEFAULT_BRANCH}" ]] || [[ ! -z "$CI_COMMIT_TAG" ]]; then
  echo "On default branch or tag, enabling all addons"
  yq e ".addons.*.enabled = "true"" $CI_VALUES_FILE > tmpfile && mv tmpfile $CI_VALUES_FILE
else
  IFS=","
  for package in $CI_MERGE_REQUEST_LABELS; do
    if [ "$(yq e ".addons.${package}.enabled" $CI_VALUES_FILE 2>/dev/null)" == "false" ]; then
      echo "Identified \"$package\" from labels"
      yq e ".addons.${package}.enabled = "true"" $CI_VALUES_FILE > tmpfile && mv tmpfile $CI_VALUES_FILE
    fi
  done
fi

# deploy BigBang using dev sized scaling
echo "Installing BigBang with the following configurations:"
cat $CI_VALUES_FILE

helm upgrade -i bigbang chart -n bigbang --create-namespace \
  --set registryCredentials[0].username='robot$bigbang' \
  --set registryCredentials[0].password="$REGISTRY1_PASSWORD" \
  --set registryCredentials[0].registry=registry1.dso.mil \
  -f ${CI_VALUES_FILE}

# apply secrets kustomization pointing to current branch
echo "Deploying secrets from the ${CI_COMMIT_REF_NAME} branch"
if [ -z "$CI_COMMIT_TAG" ]; then
  cat tests/ci/shared-secrets.yaml | sed 's|master|'"$CI_COMMIT_REF_NAME"'|g' | kubectl apply -f -
else
  # NOTE: $CI_COMMIT_REF_NAME = $CI_COMMIT_TAG when running on a tagged build
  cat tests/ci/shared-secrets.yaml | sed 's|branch: master|tag: '"$CI_COMMIT_REF_NAME"'|g' | kubectl apply -f -
fi
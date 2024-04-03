#!/bin/sh

set -e
set -x

if [ -z "$INPUT_SOURCE_FILE" ]
then
  echo "Source file must be defined"
  return 1
fi

if [ -z "$INPUT_GIT_SERVER" ]
then
  INPUT_GIT_SERVER="github.com"
fi

if [ -z "$INPUT_DESTINATION_BRANCH" ]
then
  INPUT_DESTINATION_BRANCH=main
fi
OUTPUT_BRANCH="$INPUT_DESTINATION_BRANCH"

CLONE_DIR=$(mktemp -d)

echo "Cloning destination git repository"
git config --global user.email "$INPUT_USER_EMAIL"
git config --global user.name "$INPUT_USER_NAME"
git config --global http.version HTTP/1.1
git config --global http.postBuffer 157286400
git config --global feature.manyFiles 1
git clone --depth 1 --single-branch --branch $INPUT_DESTINATION_BRANCH "https://x-access-token:$API_TOKEN_GITHUB@$INPUT_GIT_SERVER/$INPUT_DESTINATION_REPO.git" "$CLONE_DIR"

if [ ! -z "$INPUT_RENAME" ]
then
  echo "Setting new filename: ${INPUT_RENAME}"
  DEST_COPY="$CLONE_DIR/$INPUT_DESTINATION_FOLDER/$INPUT_RENAME"
else
  DEST_COPY="$CLONE_DIR/$INPUT_DESTINATION_FOLDER"
fi

# str is read into an array as tokens separated by IFS
#files=($(echo "$INPUT_SOURCE_FILE" | tr "," "\n"))

#echo each of the value to output
#for value in "${files[@]}"; do
  echo "Making sure the destination file does not exist or folder is empty."
  rm -rf "$DEST_COPY/$INPUT_SOURCE_FILE"

  echo "Copying contents to git repo"
  mkdir -p $CLONE_DIR/$INPUT_DESTINATION_FOLDER
  if [ -z "$INPUT_USE_RSYNC" ]
  then
    cp -R "$INPUT_SOURCE_FILE" "$DEST_COPY"
  else
    echo "rsync mode detected"
    rsync -avrh "$INPUT_SOURCE_FILE" "$DEST_COPY"
  fi
#done

cd "$CLONE_DIR"

if [ ! -z "$INPUT_DESTINATION_BRANCH_CREATE" ]
then
  echo "Creating new branch: ${INPUT_DESTINATION_BRANCH_CREATE}"
  git checkout -b "$INPUT_DESTINATION_BRANCH_CREATE"
  OUTPUT_BRANCH="$INPUT_DESTINATION_BRANCH_CREATE"
fi

if [ -z "$INPUT_COMMIT_MESSAGE" ]
then
  INPUT_COMMIT_MESSAGE="Update from https://$INPUT_GIT_SERVER/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA}"
fi

push_code_coverage () {
  local retries=3 # Maximum number of attempts
  for ((attempt=1; attempt <= retries; attempt++)); do
    echo "Attempt $attempt of $retries: Pushing git commit..."
    git push -u origin HEAD:"$OUTPUT_BRANCH" && return 0 # Success
    echo "Push failed. Attempting to resolve..."
    git pull --rebase # Attempt to rebase
    if [ $? -ne 0 ]; then
      echo "Rebase failed. Please resolve any conflicts manually."
      return 1 # Exit if rebase fails
    fi
  done
  echo "Push failed after $retries attempts."
  return 1
}

echo "Adding git commit"
git add .

if git status | grep -q "Changes to be committed"
then
  git commit --message "$INPUT_COMMIT_MESSAGE"
  push_code_coverage
else
  echo "No changes detected"
fi

if [ "$INPUT_DELETE_SOURCE_FILE" = "true" ]
then
  echo "Making sure the input files are destroyed."
  rm -rf "$INPUT_SOURCE_FILE"
fi



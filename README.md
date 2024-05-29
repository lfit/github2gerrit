# github2gerrit github action

This action extracts the commits from a Github pull-request and submits them
to a upstream Gerrit repository. The action allows GitHub developers to contribute to Gerrit based repositories that are primarily developed on Gerrit servers and replicated onto Github.

## Pre-requisites

1. Github Replication is setup on the Gerrit repositry over SSH. Refer to the [Gerrit replication configuration setup guide] maintained by Linux Foundation release engineering team. (https://docs.releng.linuxfoundation.org/en/latest/infra/gerrit.html)
2. Create a user account with Github with permisions to submit change to Gerrit and ensure the added on Github organization or repository as member.

## How the action works

The action and workflow is put together written in bash scripting, git and git-review.

1. The action is triggered when a new pull-request is created on Github repository
configured with the action.
2. Squash all the commits in the pull-request into a single commits.
3. Check for a change-id line present in the pull-request commit message. If its not present, add the change-Id on the commit. If the change-Id is found on any of the commits it will be reused along with the patch.
4. Create a Gerrit patch with the Change-ID, squashing all PR changes into a single commit.
5. Close the pull-request once Gerrit patch is submitted. A comment is updated to the pull-request along with the URL to the change is added to the pull request. Any updates changes will require the pull-request to be re-opened. Updates to the pull-request is done with a force push which triggers the workflows to ensure that change is re-submitted.


## Caveats - Future improvements

- Commits in a pull-request are squashed into a single commit before its submitted the change request onto Gerrit.
- Code review comments on Gerrit will not updated back on the pull-request and requires the developers to follow up on the Gerrit change request URL.

## Inputs - required

- GERRIT_KNOWN_HOSTS: known host of Gerrit repository
- GERRIT_PROJECT: Gerrit project repository
- GERRIT_SERVER: Gerrit server FQDN
- GERRIT_SSH_PRIVKEY_G2G: SSH Private key pair (The private key has to be added to the Gerrit users account settings. Gerrit -> User Settings.)
- GERRIT_SSH_USER_G2G: Gerrit Server Username (Required to connect to Gerrit)
- GERRIT_SSH_USER_G2G_EMAIL: Email of the Gerrit user.

## Inputs - optional
- ORGANIZATION: The Github Organization or project.
- REVIEWER_EMAI: Committers email list (comma separated list without spaces)

## Full Example usage with composite action

Use the composite action as step in the workflow for further processing.

```yaml
---
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024 The Linux Foundation <abelur@linux.com>

name: call-github2gerrit-composite-action

# yamllint disable-line rule:truthy
on:
  pull_request_target:
    types: [opened, reopened, edited, synchronize]
    branches:
      - master
      - main

jobs:
  call-in-g2g-workflow:
    if: false
    permissions:
      contents: read
      pull-requests: write
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
      - name: "Call the askb/github2gerrit composite action"
        id: gerrit-upload
        uses: askb/github2gerrit@main
        with:
          GERRIT_KNOWN_HOSTS: ${{ vars.GERRIT_KNOWN_HOSTS }}
          GERRIT_PROJECT: ${{ vars.GERRIT_PROJECT }}
          GERRIT_SERVER: ${{ vars.GERRIT_SERVER }}
          GERRIT_SSH_PRIVKEY_G2G: ${{ secrets.GERRIT_SSH_PRIVKEY_G2G }}
          GERRIT_SSH_USER_G2G: ${{ vars.GERRIT_SSH_USER_G2G }}
          GERRIT_SSH_USER_G2G_EMAIL: ${{ vars.GERRIT_SSH_USER_G2G_EMAIL }}
          ORGANIZATION: ${{ vars.ORGANIZATION }}

      - name: "Output change-number and change URL"
        shell: bash
        run: |
          echo "Change URL: ${{ steps.change_num.outputs.GERRIT_CHANGE_REQUEST_URL }}"
          echo "Change number: ${{ steps.change_num.outputs.GERRIT_CHANGE_REQUEST_NUMBER }}"

```

## Full Example usage with reusable workflow

Call the reusable workflow as standalone job.

```yaml
---
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024 The Linux Foundation <abelur@linux.com>

name: call-github2gerrit-reusable-workflow

# yamllint disable-line rule:truthy
on:
  workflow_dispatch:
  pull_request_target:
    types: [opened, reopened, edited, synchronize]
    branches:
      - master
      - main

concurrency:
  # yamllint disable-line rule:line-length
  group: ${{ github.workflow }}-${{ github.run_id }}
  cancel-in-progress: true

jobs:
  call-in-g2g-workflow:
    if: false
    permissions:
      contents: read
      pull-requests: write
    uses: askb/github2gerrit/.github/workflows/github2gerrit.yaml@main
    with:
      GERRIT_KNOWN_HOSTS: ${{ vars.GERRIT_KNOWN_HOSTS }}
      GERRIT_PROJECT: ${{ vars.GERRIT_PROJECT }}
      GERRIT_SERVER: ${{ vars.GERRIT_SERVER }}
      GERRIT_SSH_USER_G2G: ${{ vars.GERRIT_SSH_USER_G2G }}
      GERRIT_SSH_USER_G2G_EMAIL: ${{ vars.GERRIT_SSH_USER_G2G_EMAIL }}
      ORGANIZATION: ${{ vars.ORGANIZATION }}
    secrets:
      GERRIT_SSH_PRIVKEY_G2G: ${{ secrets.GERRIT_SSH_PRIVKEY_G2G }}

```

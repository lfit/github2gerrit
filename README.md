# github2gerrit action

The action extracts the commits from a GitHub pull-request and submits them to an upstream Gerrit repository. This allows GitHub developers to contribute to Gerrit-based repositories that are primarily maintained on Gerrit servers and replicated onto GitHub.

## Pre-requisites

1. GitHub replication is set up on the Gerrit repository over SSH. Refer to the [Gerrit replication configuration setup guide](https://docs.releng.linuxfoundation.org/en/latest/infra/gerrit.html) maintained by the Linux Foundation release engineering team. This also requires creating ssh-keypair
   and [registering the SSH keys](https://docs.releng.linuxfoundation.org/en/latest/gerrit.html#register-key-gerrit) with Gerrit.
2. Create a user account on GitHub with permissions to submit changes to Gerrit and ensure it is added to the GitHub organization or repository as a member.
3. Use a [.gitreview](https://docs.opendev.org/opendev/git-review/latest/installation.html#gitreview-file-format) file point to the Gerrit server and repository. If this not alternatively pass the GERRIT_SERVER or GERRIT_PROJECT as inputs to the workflow.

## How the Action Works

The action and workflow are written with bash scripts using well known Git SCM tools, gh, jq and git-review.

1. The action is triggered when a new pull request is created on a GitHub repository configured with the action.
2. Squash all the commits in the pull request into a single commit.
3. Check for a Change-Id line in the pull request commit message. If it is not present, add the Change-Id to the commit. If the Change-Id is found in any of the commits, it will be reused along with the patch.
4. Create a Gerrit patch with the Change-Id, squashing all PR changes into a single commit.
5. Add a pull-request reference as a comment on the Gerrit change for committers or reviewers to refer to the source of change request.
6. Close the pull request once the Gerrit patch is submitted. A comment is added to the pull request with the URL to the change. Any updates will require the pull request to be reopened. Updates to the pull request are done with a force push, which triggers the workflows to ensure the change is resubmitted.

## Features

### Use pull-request a commit message

-   Commits in a pull request are squashed into a single commit before submitting the change request to Gerrit.

### Use pull-request a commit message

-   Set the commit message as pull request body and title along with the change-Id and Signed-off-by lines. Commit message are squashed and the commit body and tittle are discarded.

## Caveats - Future Improvements

-   Commits in a pull request are submitted as independent change requests to Gerrit under the same topic.
-   Code review comments on Gerrit will not be updated back on the pull request, requiring developers to follow up on the Gerrit change request URL.

## Required Inputs

-   `GERRIT_KNOWN_HOSTS`: Known host of the Gerrit repository.
-   `GERRIT_SSH_PRIVKEY_G2G`: SSH private key pair (The private key has to be added to the Gerrit user's account settings. Gerrit -> User Settings).
-   `GERRIT_SSH_USER_G2G`: Gerrit server username (Required to connect to Gerrit).
-   `GERRIT_SSH_USER_G2G_EMAIL`: Email of the Gerrit user.

## Optional Inputs

-   `USE_PR_AS_COMMIT`: Use commit body and tittle from pull-request (Default: false)
-   `FETCH_DEPTH`: fetch-depth of the clone repo. (Default: 10)
-   `GERRIT_PROJECT`: Gerrit project repository (Default read from .gitreview).
-   `GERRIT_SERVER`: Gerrit server FQDN (Default read from .gitreview).
-   `GERRIT_SERVER_PORT`: Gerrit server port (Default: 29418)
-   `ORGANIZATION`: The GitHub Organization or Project.
-   `REVIEWER_EMAIL`: Committers' email list (comma-separated list without spaces).

## Full Example Usage with Composite Action

Use the composite action as a step in the workflow for further processing.

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
        permissions:
            contents: read
            pull-requests: write
        runs-on: ubuntu-latest
        steps:
            - uses: actions/checkout@v4
              with:
                  token: ${{ secrets.GITHUB_TOKEN }}
            - name: "Call the lfit/github2gerrit composite action"
              id: gerrit-upload
              uses: lfit/github2gerrit@main
              with:
                  FETCH_DEPTH: 10
                  GERRIT_KNOWN_HOSTS: ${{ vars.GERRIT_KNOWN_HOSTS }}
                  GERRIT_SERVER: ${{ vars.GERRIT_SERVER }}
                  GERRIT_SERVER_PORT: "29418"
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
        permissions:
            contents: read
            pull-requests: write
        uses: lfit/github2gerrit/.github/workflows/github2gerrit.yaml@main
        with:
            GERRIT_KNOWN_HOSTS: ${{ vars.GERRIT_KNOWN_HOSTS }}
            GERRIT_SSH_USER_G2G: ${{ vars.GERRIT_SSH_USER_G2G }}
            GERRIT_SSH_USER_G2G_EMAIL: ${{ vars.GERRIT_SSH_USER_G2G_EMAIL }}
            ORGANIZATION: ${{ vars.ORGANIZATION }}
        secrets:
            GERRIT_SSH_PRIVKEY_G2G: ${{ secrets.GERRIT_SSH_PRIVKEY_G2G }}
```

## Contributions

We welcome contributions! If you have any ideas, suggestions, or improvements, please feel free to open an issue or submit a pull request. Your contributions are greatly appreciated!

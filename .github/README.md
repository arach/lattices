# Hosted CI is opt in

All checked-in GitHub Actions workflows run only through `workflow_dispatch`.
Pushes, pull requests, labels, and release tags do not start hosted jobs.
This applies to build checks, package checks, releases, and site deployment
where present. Run routine validation and release builds locally.

To request a hosted run, open **Actions**, select the workflow, choose
**Run workflow**, and select the branch or tag to check. The selected ref must
contain the manual-only workflow version. Old refs can still contain historical
automatic triggers; merge or rebase the current default branch before pushing
older branches or creating release tags from them.

Publishing or uploading a release requires its explicit input (`publish`,
`publish_release`, or `upload`); leave it false for validation or artifact-only
runs. The Pages deployment workflow, where present, deploys when manually run.
Signing, notarization, and artifact verification remain part of release jobs.

Do not add automatic push, PR, schedule, or tag triggers without explicit
operator approval. A manual run opts in to that run only.

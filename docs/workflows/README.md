# Optional GitHub Actions workflow

`ci.yml` is the build/test/artifact workflow template. It is stored here because
the GitHub OAuth credential used for the initial upload does not include the
`workflow` scope. No extra account access was requested for the upload.

To enable automatic builds later, use an appropriately authorized credential and
move this file to `.github/workflows/ci.yml`. Source builds and GitHub Release
installation packages work independently of GitHub Actions.

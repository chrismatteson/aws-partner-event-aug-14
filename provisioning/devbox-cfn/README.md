# Vendored devbox CloudFormation

These templates are copied from
[unionai-oss/flyte-aws-marketplace](https://github.com/unionai-oss/flyte-aws-marketplace)
(Apache-2.0). They're vendored here so this repo is self-contained — `operator/publish.sh`
packages `devbox/cloudformation/root.yaml` directly instead of cloning the marketplace repo —
and so we can **modify them** for the workshop — the ACM `*.apps.<domain>` wildcard cert and
the Route 53 records the self-delegation model relies on.

```
devbox-cfn/
  devbox/cloudformation/
    root.yaml                 # entry point; nests the three below
    templates/compute.yaml    # EC2 + ALB + ACM + Route 53 + Cognito auth + wake/stop lambdas
  common/cloudformation/
    data.yaml                 # S3 + Aurora + ECR
    auth.yaml                 # Cognito user pool + hosted UI + M2M client
    branding/                 # Cognito hosted-UI customization (Lambda-backed)
```

The relative `TemplateURL` paths in `root.yaml` (`../../common/...`, `templates/...`) are
preserved by this layout, so `aws cloudformation package` resolves them from here.

**To pull upstream changes:** re-copy `common/cloudformation` and `devbox/cloudformation`
from the marketplace repo, then re-apply any local modifications (tracked in git history).

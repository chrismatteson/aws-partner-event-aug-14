# Operator

Two things the workshop organizer runs. Everything per-account is pure CloudFormation
([`provisioning/root.yaml`](../provisioning/)) that AWS Workshop Studio deploys directly —
there is no per-account script here.

### `delegator-role.yaml` — run once, ever

Deploy this in the **`flytedemo.app` account** (union-presales) and set the external-id
secret. It stands up a locked-down guard Lambda + a cross-account role so every attendee
account can self-delegate its own `s<hash>.flytedemo.app` subdomain at deploy time — no
per-account DNS work, nothing to touch in the parent account per attendee.

```bash
aws cloudformation deploy --stack-name flytedemo-delegator --region us-east-1 \
  --capabilities CAPABILITY_NAMED_IAM \
  --template-file operator/delegator-role.yaml \
  --parameter-overrides DelegationExternalId=<secret>
```

### `publish.sh` — run when the templates change

Packages the devbox template and uploads `root.yaml`, `devbox-root.yaml`, and
`kiro-sandbox.yaml` to the public S3 bucket that Workshop Studio (and the deploy command)
point at. Prints the `TemplatesBaseUrl`.

```bash
AWS_PROFILE=union-presales bash operator/publish.sh flytedemo-workshop-tpl-371290552455
```

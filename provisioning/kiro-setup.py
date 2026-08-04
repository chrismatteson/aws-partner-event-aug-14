#!/usr/bin/env python3
"""
Provision Kiro Web access for ONE attendee: an IAM Identity Center user + a Kiro
subscription (Pro / Pro+ / Power). After this runs, the attendee can sign in at
app.kiro.dev with that Identity Center user and drive the autonomous-agent sandbox
against the role from kiro-sandbox.yaml (which lives in THEIR own AWS account).

  python provisioning/kiro-setup.py --email student05@flytedemo.app --tier pro
  # tiers: pro | pro+ | power ; --region defaults to us-east-1 (Kiro Web preview region)

------------------------------------------------------------------------------------
WHY THIS IS A SCRIPT AND NOT CloudFormation
------------------------------------------------------------------------------------
Kiro subscription assignment is a PRIVATE Amazon Q Developer API --
`AmazonQDeveloperService.CreateAssignment` -- with no CloudFormation resource and no
boto3 client method. This script calls it with a hand-signed SigV4 request (signing
name "q", against codewhisperer.<region>.amazonaws.com), which is the exact call the
Kiro admin console makes. It is unsupported and may change without notice.
(Confirmed against AWS's own open-source `aws/amazon-q-developer-cli` SubscriptionType
enum and the community `kiro-community/bulk-create-users` reference.)

------------------------------------------------------------------------------------
HARD REQUIREMENT: an ORGANIZATION instance of IAM Identity Center
------------------------------------------------------------------------------------
CreateAssignment fails with "Account does not meet requirements" on a standalone /
account instance. The caller's account must be the MANAGEMENT account of an AWS
Organization with Identity Center enabled. Enabling that org instance is a one-time
console action (no reliable API) -- this script detects its absence and stops with
instructions rather than guessing.

RECOMMENDED TOPOLOGY (see provisioning/README.md): run this against ONE central org
Identity Center, once per attendee. The Kiro user does NOT need to live in the same
account as the sandbox role -- the role (kiro-sandbox.yaml) is assumable by the Kiro
service, so each attendee signs in with their central Kiro user and pastes THEIR OWN
account's role ARN. That keeps the one-time org-instance setup central while every
attendee's actual workload runs in their own full account.
"""
import argparse
import json
import sys
import time
import urllib.error
import urllib.request
import uuid

import boto3
import botocore.auth
import botocore.awsrequest

# Human tier -> the private API's subscriptionType (from aws/amazon-q-developer-cli).
TIER_MAP = {
    "pro": "Q_DEVELOPER_STANDALONE_PRO",
    "pro+": "Q_DEVELOPER_STANDALONE_PRO_PLUS",
    "power": "Q_DEVELOPER_STANDALONE_POWER",
}


def die(msg, code=1):
    print(f"\nERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def ensure_identity_center(session, region):
    """Return the Identity Center instance dict, creating an account instance if absent.

    Reverse-engineered: the Kiro/Q console "enable" that makes CreateAssignment work is,
    at bottom, an IAM Identity Center *account instance* (sso-admin:CreateInstance, a public
    API) -- verified by observing that clicking "enable Kiro" in a member account with no
    instance produced exactly one account-owned instance, after which CreateAssignment
    succeeded. So we can reproduce it here with no console step.
    """
    sso = session.client("sso-admin", region_name=region)

    def ready_instance():
        # An instance is only usable once it has an IdentityStoreId (it's blank while the
        # freshly-created instance is still CREATE_IN_PROGRESS).
        for i in sso.list_instances().get("Instances", []):
            if i.get("IdentityStoreId"):
                return i
        return None

    inst = ready_instance()
    if not inst:
        # A raw sso-admin:CreateInstance account instance IS accepted by Kiro's CreateProfile
        # -- as long as CreateProfile's identitySource uses ssoRegion (not identityStoreId).
        # (Deleting an instance kicks off async SLR cleanup that briefly blocks CreateInstance,
        # so retry on that.)
        print("no Identity Center instance -> creating one (sso-admin:CreateInstance)...")
        for _ in range(20):
            try:
                sso.create_instance(Name="kiro-workshop")
                break
            except Exception as e:
                if "Service-linked role" in str(e) or "Conflict" in str(e):
                    time.sleep(15); continue
                die(f"CreateInstance failed: {e}")
        for _ in range(60):
            inst = ready_instance()
            if inst:
                break
            time.sleep(2)
    if not inst:
        die("no IAM Identity Center instance (and creation disabled/failed).")
    print(
        f"Identity Center: {inst['InstanceArn']}\n"
        f"  identity store : {inst['IdentityStoreId']}\n"
        f"  owner account  : {inst.get('OwnerAccountId', '?')}"
    )
    return inst


def ensure_service_linked_role(session):
    """Kiro/user-subscriptions needs AWSServiceRoleForUserSubscriptions. Create if missing."""
    iam = session.client("iam")
    try:
        iam.create_service_linked_role(AWSServiceName="user-subscriptions.amazonaws.com")
        print("created service-linked role AWSServiceRoleForUserSubscriptions")
    except Exception as exc:  # already exists / no permission -> continue, CreateAssignment will tell us
        if "has been taken" not in str(exc) and "already exists" not in str(exc).lower():
            print(f"  (service-linked role: {exc})", file=sys.stderr)


def find_or_create_user(session, region, store_id, email, given, family):
    """Idempotent: return the Identity Center user id for `email`, creating it if absent."""
    ids = session.client("identitystore", region_name=region)
    found = ids.list_users(
        IdentityStoreId=store_id,
        Filters=[{"AttributePath": "UserName", "AttributeValue": email}],
    ).get("Users", [])
    if found:
        print(f"Identity Center user (existing): {email}")
        return found[0]["UserId"]
    created = ids.create_user(
        IdentityStoreId=store_id,
        UserName=email,
        DisplayName=email,
        Name={"GivenName": given, "FamilyName": family},
        Emails=[{"Value": email, "Type": "work", "Primary": True}],
    )
    print(f"Identity Center user (created): {email}")
    return created["UserId"]


def _q_api(session, region, target, body, signing_name="q", max_retries=5):
    """SigV4-signed POST to the private Q Developer / CodeWhisperer admin endpoint.

    `target` is the X-Amz-Target; `signing_name` is the SigV4 service the call must be scoped
    to -- it DIFFERS by operation: AmazonQDeveloperService.* (assignments) => 'q', but
    AWSCodeWhispererService.* (profiles) => 'codewhisperer' (the service rejects 'q' with
    "Credential should be scoped to correct service: 'codewhisperer'"). Returns (ok, text).
    """
    creds = session.get_credentials().get_frozen_credentials()
    url = f"https://codewhisperer.{region}.amazonaws.com/"
    payload = json.dumps(body)
    headers = {"Content-Type": "application/x-amz-json-1.0", "X-Amz-Target": target}
    for attempt in range(max_retries + 1):
        signed = botocore.awsrequest.AWSRequest(method="POST", url=url, data=payload, headers=headers)
        botocore.auth.SigV4Auth(creds, signing_name, region).add_auth(signed)
        req = urllib.request.Request(url, data=payload.encode(), headers=dict(signed.headers), method="POST")
        try:
            return True, urllib.request.urlopen(req, timeout=30).read().decode()
        except urllib.error.HTTPError as exc:
            err = exc.read().decode()
            if exc.code == 429 and attempt < max_retries:       # throttling -> backoff
                time.sleep(min(30 * 2 ** attempt, 300))
                continue
            return False, f"HTTP {exc.code}: {err}"
        except Exception as exc:
            return False, str(exc)
    return False, "max retries exceeded"


def ensure_profile(session, region, instance_arn):
    """Ensure the account's Kiro/Q Developer PROFILE exists -- this is what the console's
    'enable Kiro' creates, and what CreateAssignment needs (else kiro.controlplane
    ResourceNotFound). Idempotent via ListProfiles. Uses the private Consolas admin API
    (AWSCodeWhispererService.*), reverse-engineered from aws/amazon-q-developer-cli."""
    arn = None
    ok, resp = _q_api(session, region, "AWSCodeWhispererService.ListProfiles", {},
                      signing_name="codewhisperer")
    if ok:
        try:
            profiles = json.loads(resp).get("profiles", [])
            if profiles:
                arn = profiles[0].get("arn") or profiles[0].get("profileArn")
                print(f"Kiro profile (existing): {arn}")
        except Exception:
            pass
    if not arn:
        print("no Kiro profile -> creating one (AWSCodeWhispererService.CreateProfile)...")
        ok, resp = _q_api(session, region, "AWSCodeWhispererService.CreateProfile", {
            "profileName": "kiro-workshop",
            "referenceTrackerConfiguration": {"recommendationsWithReferences": "ALLOW"},
            "activeFunctionalities": ["ANALYSIS", "CONVERSATIONS", "TASK_ASSIST", "TRANSFORMATIONS", "COMPLETIONS"],
            # ssoRegion, NOT identityStoreId -- the wrong field is what caused "Invalid identity
            # center configuration". Confirmed against the console's own CreateProfile call.
            "identitySource": {"ssoIdentitySource": {"instanceArn": instance_arn, "ssoRegion": region}},
            "clientToken": str(uuid.uuid4()),
        }, signing_name="codewhisperer")
        if not ok and "already" not in resp.lower():
            die(f"CreateProfile failed: {resp}")
        try:
            arn = json.loads(resp).get("arn") or json.loads(resp).get("profileArn")
        except Exception:
            pass
        print(f"Kiro profile: {arn or '(created)'}")
    # Enable Kiro Web (autonomous agents) on the profile. CreateProfile does NOT set it -- the
    # console does a follow-up UpdateProfile with optInFeatures.autonomousAgents.toggle=ON, and
    # without it app.kiro.dev Web isn't enabled. (Payload confirmed from the console's HAR.)
    if arn:
        ok, resp = _q_api(session, region, "AWSCodeWhispererService.UpdateProfile", {
            "profileArn": arn,
            "profileName": "kiro-workshop",
            "identitySource": {"ssoIdentitySource": {"instanceArn": instance_arn, "ssoRegion": region}},
            "optInFeatures": {"overageConfiguration": {"overageStatus": "DISABLED"},
                              "autonomousAgents": {"toggle": "ON"}},
            "optInFeaturesType": "KIRO",
            "referenceTrackerConfiguration": {"recommendationsWithReferences": "ALLOW"},
            "activeFunctionalities": ["ANALYSIS", "CONVERSATIONS", "TASK_ASSIST", "TRANSFORMATIONS", "COMPLETIONS"],
        }, signing_name="codewhisperer")
        print(f"Kiro Web (autonomous agents): {'ON' if ok else 'FAILED: ' + resp[:140]}")
    return arn


def create_assignment(session, region, principal_id, subscription_type,
                      principal_type="USER", profile_arn=None, max_retries=6):
    """Assign a Kiro subscription via the private AmazonQDeveloperService.CreateAssignment.

    Right after a profile is created the account is briefly "not authorized" for assignments,
    so retry on that transient AccessDenied.
    """
    body = {"principalId": principal_id, "principalType": principal_type,
            "subscriptionType": subscription_type}
    if profile_arn:
        body["profileArn"] = profile_arn
    resp = ""
    for attempt in range(max_retries):
        ok, resp = _q_api(session, region, "AmazonQDeveloperService.CreateAssignment", body)
        if ok:
            return True, ""
        low = resp.lower()
        # already subscribed -> idempotent success. A Conflict / "invalid state" on re-run
        # means the assignment is already there.
        if "already" in low or "conflict" in low or "invalid state" in low:
            return True, "already assigned"
        if "not author" in low and attempt < max_retries - 1:
            time.sleep(10)
            continue
        return False, resp
    return False, resp


def generate_otp_password(session, region, store_id, user_id):
    """Generate a one-time login password for the Identity Center user via the private
    SWBUPService.UpdatePassword (PasswordMode OTP) -- signed as 'userpool' on the identitystore
    endpoint. Returns the password string (the user is prompted to change it on first login),
    or None. Confirmed from the console's own reset-password call."""
    creds = session.get_credentials().get_frozen_credentials()
    url = f"https://identitystore.{region}.amazonaws.com/"
    body = json.dumps({"UserId": user_id, "PasswordMode": "OTP", "IdentityStoreId": store_id})
    signed = botocore.awsrequest.AWSRequest(method="POST", url=url, data=body, headers={
        "Content-Type": "application/x-amz-json-1.0", "X-Amz-Target": "SWBUPService.UpdatePassword"})
    botocore.auth.SigV4Auth(creds, "userpool", region).add_auth(signed)
    req = urllib.request.Request(url, data=body.encode(), headers=dict(signed.headers), method="POST")
    try:
        return json.loads(urllib.request.urlopen(req, timeout=30).read().decode()).get("Password")
    except Exception as exc:
        print(f"  (one-time password generation failed: {exc})", file=sys.stderr)
        return None


def main():
    ap = argparse.ArgumentParser(description="Create an Identity Center user + Kiro subscription.")
    ap.add_argument("--email", required=True, help="attendee's Identity Center username/email")
    ap.add_argument("--tier", default="pro", choices=list(TIER_MAP), help="Kiro plan (default pro)")
    ap.add_argument("--region", default="us-east-1", help="Kiro Web preview region (default us-east-1)")
    ap.add_argument("--given-name", default="Workshop")
    ap.add_argument("--family-name", default="Attendee")
    args = ap.parse_args()

    subscription_type = TIER_MAP[args.tier]
    session = boto3.Session()

    inst = ensure_identity_center(session, args.region)
    ensure_service_linked_role(session)
    profile_arn = ensure_profile(session, args.region, inst["InstanceArn"])
    user_id = find_or_create_user(
        session, args.region, inst["IdentityStoreId"],
        args.email, args.given_name, args.family_name,
    )
    print(f"  user id        : {user_id}")

    ok, note = create_assignment(session, args.region, user_id, subscription_type,
                                 profile_arn=profile_arn)
    if not ok:
        die(
            f"CreateAssignment failed: {note}\n"
            "  If it says 'Account does not meet requirements', this Identity Center is a\n"
            "  standalone/account instance -- Kiro requires an ORGANIZATION instance."
        )
    print(f"Kiro subscription assigned: {args.tier} ({subscription_type})"
          f"{'  [' + note + ']' if note else ''}")

    password = generate_otp_password(session, args.region, inst["IdentityStoreId"], user_id)

    print(
        "\nKIRO WEB LOGIN:\n"
        f"  URL      : https://app.kiro.dev\n"
        f"  username : {args.email}\n"
        f"  password : {password or '(generation failed -- reset in the Identity Center console)'}\n"
        "             (one-time; you'll set a new one on first sign-in)\n\n"
        "Then paste the sandbox role ARN (kiro-sandbox output) at Settings > Agent > Sandbox >\n"
        "IAM Role, set the allow-list + MCP server, and run `bash scripts/bootstrap.sh` in a task."
    )


if __name__ == "__main__":
    main()

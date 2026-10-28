"""Unit tests for Phase 1 (P0) Security, Auth, JWT, Billing Verification, and Upload Validation."""
from __future__ import annotations

import hashlib
import os
import sys
import unittest

os.environ["VP_IN_MEMORY_DB"] = "1"
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from fastapi import HTTPException  # noqa: E402
from starlette.requests import Request  # noqa: E402

from app.auth import (  # noqa: E402
    create_access_token,
    create_refresh_token,
    decode_token,
    get_current_user,
    hash_password,
    rate_limiter,
    require_admin,
    validate_audio_upload,
    verify_password,
)
from app.db import reset_db_for_tests  # noqa: E402
from app.main import (  # noqa: E402
    admin_create_plan,
    admin_delete_user,
    api_admin_state,
    api_app_bootstrap,
    api_billing_verify,
    api_login,
    api_refresh_token,
    api_signup,
    api_user_subscribe,
)
from app.schemas import (  # noqa: E402
    AdminCreatePlanRequest,
    BillingVerifyRequest,
    LoginRequest,
    RefreshTokenRequest,
    SignupRequest,
)


def _fake_request(ip: str = "127.0.0.1") -> Request:
    scope = {
        "type": "http",
        "method": "POST",
        "path": "/",
        "headers": [],
        "client": (ip, 12345),
    }
    return Request(scope)


class P0SecurityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.db = reset_db_for_tests()
        rate_limiter.reset()

    def test_scrypt_password_hashing_uses_unique_per_user_salt(self) -> None:
        h1 = hash_password("CorrectHorseBatteryStaple!")
        h2 = hash_password("CorrectHorseBatteryStaple!")
        self.assertTrue(h1.startswith("scrypt$"))
        self.assertNotEqual(h1, h2, "Two hashes of the same password must have distinct random salts")

        valid, needs_rehash = verify_password("CorrectHorseBatteryStaple!", h1)
        self.assertTrue(valid)
        self.assertFalse(needs_rehash)

        wrong, _ = verify_password("WrongPassword123", h1)
        self.assertFalse(wrong)

    def test_legacy_sha256_hash_migrates_automatically_on_login(self) -> None:
        legacy_hash = hashlib.sha256(b"vp_salt_legacyPass99").hexdigest()
        self.db.users.update_one(
            {"email": "maya.vocals@soundlab.co"},
            {"$set": {"password_hash": legacy_hash}},
        )

        res = api_login(
            LoginRequest(email="maya.vocals@soundlab.co", password="legacyPass99"),
            _fake_request(),
        )
        self.assertIn("access_token", res)
        self.assertIn("refresh_token", res)

        updated = self.db.users.find_one({"email": "maya.vocals@soundlab.co"})
        self.assertTrue(
            updated["password_hash"].startswith("scrypt$"),
            "Legacy SHA-256 hash should be transparently upgraded to scrypt on login",
        )

    def test_login_rejects_unknown_email_and_wrong_password(self) -> None:
        with self.assertRaises(HTTPException) as ctx_unknown:
            api_login(
                LoginRequest(email="stranger@unknown.io", password="password123"),
                _fake_request(),
            )
        self.assertEqual(ctx_unknown.exception.status_code, 401)
        self.assertIsNone(
            self.db.users.find_one({"email": "stranger@unknown.io"}),
            "Unknown email must NOT auto-provision an account on login",
        )

        with self.assertRaises(HTTPException) as ctx_wrong_pw:
            api_login(
                LoginRequest(email="alex@podcaststudio.io", password="wrongPassword"),
                _fake_request(),
            )
        self.assertEqual(ctx_wrong_pw.exception.status_code, 401)

    def test_jwt_tampering_and_refresh_flow(self) -> None:
        access = create_access_token("USR-1041", "alex@podcaststudio.io", role_type="admin")
        claims = decode_token(access, expected_type="access")
        self.assertEqual(claims["sub"], "USR-1041")
        self.assertEqual(claims["role_type"], "admin")

        # Tamper with signature
        tampered = access[:-4] + "AAAA"
        with self.assertRaises(HTTPException) as ctx:
            decode_token(tampered)
        self.assertEqual(ctx.exception.status_code, 401)

        # Refresh token exchange
        refresh = create_refresh_token("USR-1041", "alex@podcaststudio.io", role_type="admin")
        refreshed = api_refresh_token(RefreshTokenRequest(refresh_token=refresh))
        self.assertIn("access_token", refreshed)
        self.assertEqual(refreshed["user"]["id"], "USR-1041")

    def test_admin_endpoints_enforce_jwt_and_admin_role(self) -> None:
        # 1. Missing token -> 401
        with self.assertRaises(HTTPException) as ctx_no_auth:
            get_current_user(None)
        self.assertEqual(ctx_no_auth.exception.status_code, 401)

        # 2. Regular user token -> 403 on require_admin
        user_token = create_access_token("USR-1042", "maya.vocals@soundlab.co", role_type="user")
        regular_user = get_current_user(f"Bearer {user_token}")
        with self.assertRaises(HTTPException) as ctx_forbidden:
            require_admin(regular_user)
        self.assertEqual(ctx_forbidden.exception.status_code, 403)

        # 3. Admin user token -> 200 on admin endpoints
        admin_token = create_access_token("USR-1041", "alex@podcaststudio.io", role_type="admin")
        admin_user = require_admin(get_current_user(f"Bearer {admin_token}"))
        state = api_admin_state(admin_user)
        self.assertIn("metrics", state)

        plan_doc = admin_create_plan(
            AdminCreatePlanRequest(
                name="Studio Ultra",
                badge="ULTRA",
                monthly_price=39.99,
                yearly_price=24.99,
                description="Ultra tier",
                perks=["Lossless stems"],
                popular=False,
            ),
            admin_user,
        )
        self.assertEqual(plan_doc["name"], "Studio Ultra")

        deleted = admin_delete_user("USR-1044", admin_user)
        self.assertEqual(deleted["deleted"], "USR-1044")

    def test_bootstrap_does_not_leak_user_when_unauthenticated(self) -> None:
        anon_boot = api_app_bootstrap(user=None)
        self.assertIsNone(
            anon_boot["user"],
            "Unauthenticated bootstrap call must never leak another user's profile",
        )

    def test_signup_blocks_duplicate_email_overwrite(self) -> None:
        res = api_signup(
            SignupRequest(
                name="New Podcaster",
                email="newcreator@studio.io",
                password="securePassword123",
                role="Podcaster",
            ),
            _fake_request(),
        )
        self.assertEqual(res["user"]["email"], "newcreator@studio.io")

        with self.assertRaises(HTTPException) as ctx_dup:
            api_signup(
                SignupRequest(
                    name="Attacker Overwrite",
                    email="newcreator@studio.io",
                    password="otherPassword123",
                    role="Podcaster",
                ),
                _fake_request(),
            )
        self.assertEqual(ctx_dup.exception.status_code, 409)

    def test_billing_enforces_server_side_plan_price_and_blocks_replay(self) -> None:
        maya = self.db.users.find_one({"id": "USR-1042"})
        initial_spent = float(maya["total_spent_usd"])

        # Verify via /api/billing/verify (Studio AI Pro Yearly = $7.99 * 12 = $95.88)
        res = api_billing_verify(
            BillingVerifyRequest(
                plan_name="Studio AI Pro",
                billing_cycle="Yearly",
                provider="google_play",
                purchase_token="gp_token_unique_1001",
            ),
            user=maya,
        )
        self.assertAlmostEqual(res["verified_amount_usd"], 95.88, places=2)
        self.assertAlmostEqual(
            res["user"]["total_spent_usd"], initial_spent + 95.88, places=2
        )

        # Replay of same purchase_token must fail with 409
        with self.assertRaises(HTTPException) as ctx_replay:
            api_billing_verify(
                BillingVerifyRequest(
                    plan_name="Studio AI Pro",
                    billing_cycle="Yearly",
                    provider="google_play",
                    purchase_token="gp_token_unique_1001",
                ),
                user=maya,
            )
        self.assertEqual(ctx_replay.exception.status_code, 409)

        # Even if client sends spoofed amount_usd=0.01 to /api/users/{id}/subscribe, server uses $14.99 (Monthly)
        sub_res = api_user_subscribe(
            "USR-1042",
            {
                "plan_name": "Studio AI Pro",
                "billing_cycle": "Monthly",
                "amount_usd": 0.01,
                "purchase_token": "gp_token_unique_1002",
            },
            caller=maya,
        )
        self.assertAlmostEqual(sub_res["verified_amount_usd"], 14.99, places=2)

    def test_audio_upload_magic_byte_validation(self) -> None:
        wav_bytes = b"RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00"
        self.assertEqual(validate_audio_upload(wav_bytes, "audio/wav"), "wav")

        mp3_bytes = b"ID3\x04\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        self.assertEqual(validate_audio_upload(mp3_bytes, "audio/mpeg"), "mp3")

        flac_bytes = b"fLaC\x00\x00\x00\x22\x12\x00\x12\x00\x00\x00\x00\x00"
        self.assertEqual(validate_audio_upload(flac_bytes, "audio/flac"), "flac")

        # Disguised HTML/script upload must be rejected with 415
        bad_bytes = b"<!DOCTYPE html><html><script>alert(1)</script></html>"
        with self.assertRaises(HTTPException) as ctx_bad:
            validate_audio_upload(bad_bytes, "audio/wav")
        self.assertEqual(ctx_bad.exception.status_code, 415)


if __name__ == "__main__":
    unittest.main()

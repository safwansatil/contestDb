# Authentication Architecture & Security Strategy

This document details the architectural decisions and security best practices implemented for user registration and authentication in **ContestDB**.

---

## 1. Database-Native Hashing (Thin-Tier Alignment)

To maintain ContestDB's architectural mandate of a **thin application tier** and a **smart database brain**, user credentials are encrypted and verified directly in the database.

* **pgcrypto Extension**: We utilize PostgreSQL's standard `pgcrypto` module to handle cryptography.
* **Bcrypt Hashing**: Passwords are saved using standard blowfish/bcrypt (`bf`) hashing via:
  ```sql
  crypt(p_password, gen_salt('bf'))
  ```
  * `gen_salt('bf')` automatically generates a secure, random salt per row, rendering rainbow table attacks useless.
  * Bcrypt is an adaptive hashing algorithm designed to be slow, protecting against brute-force password guessing.
* **Stored Functions**: The API gateway never queries raw tables or manually calculates hashes. It delegates directly to:
  * `register_user(p_username, p_password)`: Registers a user, hashing their password.
  * `verify_user_credentials(p_username, p_password)`: Matches username and credentials.

---

## 2. Token-Based Session Strategy

Upon successful login or registration, the API gateway generates a stateless **JSON Web Token (JWT)**.

* **Stateless Scaling**: The token stores the user's ID (`sub`) and username. The API gateway verifies the token signature on incoming requests without querying the database, matching the "thin-tier" design.
* **Signature Verification**: Tokens are signed using `HS256` (HMAC SHA-256) with a secret key (`JWT_SECRET`) loaded from `.env`.
* **Short Expiry Window**: Tokens expire automatically in 24 hours (`TOKEN_EXPIRE_MINUTES = 1440`). This limits the exposure time in case a token is compromised.

---

## 3. Storage & Transport Best Practices

### LocalStorage vs. HttpOnly Cookies
* **Implementation Choice**: For simplicity, integration with REST tools, and compatibility with the single-page application dashboard, tokens are stored in the browser's `localStorage` and sent via the `Authorization: Bearer <token>` header.
* **Security Implications**: `localStorage` is vulnerable to Cross-Site Scripting (XSS) attacks if malicious scripts execute on the client. 
* **Production Recommendation**: For production systems, it is recommended to transition to **Secured HttpOnly Cookies** with the `SameSite=Strict` flag. This prevents JavaScript from accessing the token, eliminating XSS extraction risk.

---

## 4. Submission Identity Spoofing Prevention

In the Walking Skeleton (v0.1.3), the `/submissions` endpoint trusted the user ID passed in the JSON payload body. This allowed a user to submit telemetry under anyone else's ID.

* **Secure Resolution**: The updated `/submissions` endpoint requires authentication.
* **Omission of Body Parameter**: The client no longer passes a `user_id` in the submission JSON.
* **Token-Derived ID**: The API gateway decodes the JWT token, extracts the authenticated `user_id` from the token payload, and uses that ID for database checks and insertion. Spoofing another user's submissions is mathematically impossible without their private credentials.

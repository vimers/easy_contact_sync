---
title: Sync with Synology Contacts (CardDAV)
layout: page
---

This guide walks you through syncing the address books on your Synology NAS
(running the **Synology Contacts** package) with EasyContactSync.

EasyContactSync speaks the standard **CardDAV** protocol (RFC 6352), which
Synology Contacts supports natively — no extra plugin is needed on the phone.

**Quick start**

1. In Synology Contacts, open an address book → **⋮ → CardDAV** to get a
   CardDAV URL and a QR code.
2. In EasyContactSync: **Settings → Add Account** → tap the **QR icon** next
   to *Server URL* → scan the code → enter your username + password →
   **Test Connection** → **Save**.
3. Open the **Sync** tab and tap the sync button to pull your contacts down.

> ⚠️ **Use a trusted HTTPS certificate.** EasyContactSync can't accept the
> NAS's self-signed cert — set up a Let's Encrypt certificate (or a reverse
> proxy with a valid cert) first. See
> [Part 1.3](#13-use-a-trusted-https-certificate-important).

---

## Prerequisites

- A Synology NAS running **DSM 7.x** with the **Synology Contacts** package
  installed, and your contacts already in it.
- A Synology user account that owns (or has read/write access to) the address
  book you want to sync.
- A **trusted TLS certificate** in front of the CardDAV URL — e.g. a Let's
  Encrypt certificate on a DDNS domain, or a reverse proxy with a valid cert.
  (See [1.3](#13-use-a-trusted-https-certificate-important) for why.)
- For access from outside your home network: a **DDNS hostname** plus **port
  forwarding** on your router. (Synology's **QuickConnect does not work for
  CardDAV**.)

---

## How it works

EasyContactSync connects to your Synology Contacts server over CardDAV
(HTTPS), authenticates with your DSM username + password, and keeps the
address book in two-way sync: contacts you add or edit on the phone are pushed
to the NAS, and changes on the NAS (or in the Synology Contacts web UI) are
pulled down. Your password is encrypted on-device using the Android Keystore /
iOS Keychain.

---

## Part 1 — Prepare your Synology NAS

### 1.1 Install Synology Contacts

If you haven't already: open **Package Center** → search for **Contacts** →
**Install**. Launch it and confirm your contacts live in an address book (the
default personal address book is **My Contacts**).

![Synology Contacts package]({{ site.baseurl }}/images/synology-contacts-install.png)

### 1.2 Get your address book's CardDAV URL or QR code

This is the address — and the QR — that EasyContactSync will connect to.

1. In Synology Contacts, locate the address book you want to sync
   (e.g. *My Contacts*).
2. Click **⋮** on the right side of the address book → **CardDAV**.

   ![In Synology Contacts, click ⋮ next to the address book (e.g. My Contacts) and choose CardDAV]({{ site.baseurl }}/images/synology-contacts-carddav.png)

3. The **CardDAV Account** dialog shows the **CardDAV URL** and a **QR-code
   icon**. Tap that icon to reveal the scannable **QR code**, then leave it on
   screen — you'll scan it with EasyContactSync in a moment.

The URL looks like:

```
https://<your-nas>:5001/carddav/<username>/
```

Adjust the host and port to match your setup. If the NAS is behind a reverse
proxy on a domain, it becomes `https://contacts.example.com/carddav/<username>/`
on the default HTTPS port (443).

![The CardDAV Account dialog: it shows the CardDAV URL plus a QR-code icon — tap the icon to display the scannable QR code]({{ site.baseurl }}/images/synology-carddav-qr.png)

> 📱 **Scan the QR instead of typing.** EasyContactSync has a built-in scanner
> that fills the *Server URL* field from the QR in one tap (see Part 2.2).

### 1.3 Use a trusted HTTPS certificate (important)

EasyContactSync uses the device's standard HTTPS stack and **does not trust
self-signed certificates**. If you point it at `https://<nas-ip>:5001` with the
NAS's default self-signed certificate, the connection fails with a TLS/handshake
error. You have two solid options:

**Option A — Let's Encrypt on a DDNS domain (recommended; works remotely)**

1. Set up a free DDNS hostname: **Control Panel → External Access → DDNS →
   Add** (Synology provides a free `*.synology.me` provider).
2. Forward ports **80 and 443** on your router to the NAS.
3. Issue a certificate: **Control Panel → Security → Certificate → Add → Add a
   certificate → Get a certificate from Let's Encrypt**. Enter your DDNS domain
   and email; add the domain to *Subject Alternative Name* if needed.
4. Make the new certificate the **default** (or assign it specifically to
   Synology Contacts).

**Option B — Reverse proxy with a valid certificate (good for LAN, or for
sharing one domain across several services)**

1. **Control Panel → Login Portal → Advanced → Reverse Proxy → Create**.
2. *Source*: `https://contacts.example.com` (port 443, HTTPS).
   *Destination*: `localhost`, port **5001**, protocol **HTTPS** (DSM serves
   port 5001 over HTTPS).
3. Under the rule's **Settings**, assign your valid certificate
   (e.g. a wildcard Let's Encrypt cert).
4. Use `https://contacts.example.com/carddav/<username>/` as the CardDAV URL
   (port 443 implied).

> 🔒 **QuickConnect won't work.** CardDAV needs a real domain name or IP
> reachable over the internet — Synology's QuickConnect relay does not proxy
> CardDAV. Use DDNS + port forwarding for remote sync.

### 1.4 Username and 2-factor verification notes

- **No app-specific passwords on Synology.** Unlike Google or Apple, Synology
  (as of DSM 7) does **not** let you generate app passwords for third-party
  CardDAV clients — you use your normal DSM password.
- **If 2-step verification is enabled** on the account, it **blocks**
  third-party CardDAV clients. Pick one:
  - Use a **dedicated Synology account without 2FA** just for contacts sync
    (cleanest), or
  - Switch your main account to **Synology Secure Sign In** (password-free
    login for the web UI / DS apps) and keep a long random password for
    CardDAV clients like EasyContactSync.
- **Avoid usernames with spaces.** Synology's CardDAV resource discovery is
  known to break on usernames that contain spaces — rename the account if
  needed.
- **iOS only:** account names or paths containing non-English (non-ASCII)
  characters can fail to sync via CardDAV.

### 1.5 Open remote access (only if syncing away from home)

- On your router, forward the port your CardDAV URL uses (443 for a reverse
  proxy / Let's Encrypt domain, or 5001 directly) to the NAS.
- Use your **DDNS hostname** — not your LAN IP — as the host in the CardDAV URL
  when you're away from home.

---

## Part 2 — Add the account in EasyContactSync

### 2.1 Open Add Account

Open EasyContactSync → tap the **Settings** tab in the bottom navigation →
under **CardDAV Accounts**, tap **Add Account**.

![Add Account screen]({{ site.baseurl }}/images/app-add-account.png)

### 2.2 Fill the Server URL — scan the QR (recommended)

You have two ways:

- **Scan (recommended):** tap the **QR-code icon** next to the *Server URL*
  field, then point your camera at the **CardDAV QR code** shown in Synology
  Contacts (from step 1.2). The URL fills in automatically.
- **Paste:** copy the CardDAV URL from Synology Contacts and paste it into
  *Server URL*.

> ℹ️ The QR fills **only the Server URL**. You still type your username and
> password yourself.

### 2.3 Enter username and password

- **Username:** your Synology DSM username (no spaces — see
  [1.4](#14-username-and-2-factor-verification-notes)).
- **Password:** your DSM account password.

### 2.4 Test Connection

Tap **Test Connection**. EasyContactSync sends a PROPFIND to the server and
reports one of:

- ✅ **"Connection successful"** — you're good. Proceed to Save.
- 🔴 **"authentication failed (401/403)"** — username or password is wrong.
- 🔴 **"Server returned status …"** — the URL is reachable but something's off,
  usually the path. Make sure you used the full `/carddav/<username>/` URL (or
  scanned the QR).
- 🔴 **"Connection failed …"** — couldn't reach or talk to the server. The most
  common cause is a **self-signed certificate** (fix in
  [1.3](#13-use-a-trusted-https-certificate-important)); it can also mean the
  NAS isn't reachable from where the phone currently is.

> ⚠️ **Don't hammer Test Connection with a wrong password.** Synology
> **auto-blocks IPs** after a few failed logins. If you get locked out, go to
> **DSM → Control Panel → Security → Account → Allow/Block list**, find your
> IP, and remove it.

### 2.5 Save

Tap **Save**. The account is stored, and your password is encrypted with the
Android Keystore / iOS Keychain.

---

## Part 3 — First sync and everyday use

### 3.1 Grant the contacts permission

On first use, EasyContactSync asks for permission to read and write your
phone's contacts — allow it, otherwise sync has nowhere to write.

### 3.2 Run your first sync

Tap the **Sync** tab in the bottom navigation → tap the **manual-sync button**.
The first sync pulls your NAS address book down to the phone. You can also
pull-to-refresh on this page.

### 3.3 Set how often it syncs in the background

**Settings → Sync Settings → Sync Frequency** → choose **15 min / 30 min /
1 hour / 6 hours / Manual only**. (Background sync is best-effort and subject
to the OS's power rules.)

### 3.4 Diffs, conflicts, and multiple address books

- **Per-contact sync status** — each contact shows whether it's local-only,
  remote-only, in sync, or *differing*. Differing contacts open a
  **field-level diff** so you can choose what to keep.
- **Conflicts** — when a contact changed on both sides, resolve them in bulk or
  one-by-one from the Sync tab.
- **Deletions** — deleting a contact is queued for a deletion review, so an
  accidental delete isn't pushed straight to the server.
- **Multiple address books** — add another account (or another of the NAS's
  address books) the same way.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| "Connection failed" / TLS handshake error | Self-signed cert (the NAS default) | Deploy a **trusted certificate** — [1.3](#13-use-a-trusted-https-certificate-important) |
| 401 / 403 authentication failed | Wrong username or password | Re-check credentials; mind case |
| Worked before, now all logins fail | Your IP got auto-blocked by DSM | Unblock it: **Control Panel → Security → Account → Allow/Block list** |
| "could not find principal" / 404 | Server URL is just the bare host | Use the full **`/carddav/<username>/`** URL, or scan the QR |
| Can't reach the NAS from outside | QuickConnect or wrong host | Use a **DDNS hostname** + port forwarding; QuickConnect doesn't do CardDAV |
| Resource discovery fails | Username contains spaces | Rename the account to remove spaces ([1.4](#14-username-and-2-factor-verification-notes)) |
| iOS account won't sync | Username/path has non-ASCII chars | Use ASCII-only username/path |
| 500 Internal Server Error on import | Imported a vCard 2.1 file into Synology | Import/export via the phone instead; don't drag old `.vcf` exports into the NAS CardDAV server |
| Contacts don't appear after sync | Contacts permission off, or Manual-only | Allow the contacts permission; trigger a manual sync |

---

## References

- [EasyContactSync](https://github.com/vimers/easy_contact_sync) — the app's
  GitHub repo and issue tracker
- [CardDAV protocol — RFC 6352](https://datatracker.ietf.org/doc/html/rfc6352)
- [Synology KB: How do I sync Synology Contacts with CardDAV clients?](https://kb.synology.com/DSM/tutorial/How_to_use_CardDAV_to_sync_Synology_Contacts)
- [Synology KB: Manage Address Books and Contacts](https://kb.synology.com/en-us/DSM/help/Contacts/contacts_setup_addressbook_contact?version=7) —
  where the CardDAV URL / QR code lives
- [DAVx⁵ — tested with Synology DSM](https://www.davx5.com/tested-with/synology) —
  reference notes on Synology CardDAV quirks (2FA, IP blocking, QuickConnect)
  from a fellow CardDAV client

---

*Guide for EasyContactSync — open source, MIT licensed.*

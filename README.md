# Snapcircle

A minimal, animated photo space for two friends. Static HTML, CSS and JavaScript on GitHub Pages; Supabase handles email/password login, PostgreSQL data, private uploads, circle access and points.

## Features

- Eight dedicated tabs: Overview, Photo wall, Snaps, Albums, Inventory, Leaderboard, My circle and Settings.
- Floating SVG artwork, animated page transitions, hover interactions, keyboard focus, dark mode and reduced-motion support.
- Email/password signup, confirmation, sign-in, sign-out and password reset.
- Compressed JPEG uploads, captions, album assignment, favorites, search, sorting and grid/list views.
- Snaps accessible to the circle for 24 hours. Expired snaps remain stored for lifetime point accounting; they are hidden from the shared feed.
- Server-calculated points: 10 per photo, 15 per snap; 20 uploads per person per day.
- Cosmetic inventory with server-validated redemption, equipped themes and photo frames, and milestone badges.
- Invite codes join a shared circle; anyone holding a circle code can join it. Keep codes within your intended group.
- Preview mode stores sample illustrations and uploads in IndexedDB on the current device. It is explicitly separate from real accounts.

## Current backend

The Supabase project is already provisioned and the schema is applied:
- Project: Snapcircle
- Project ref: tgodplfrmzzxkioxtcbe
- Region: Mumbai (ap-south-1)
- Database and private storage policies: enabled
- Public client configuration: site/config.js

The publishable key in config.js is designed for browser use. Never put a service-role key, database password or personal access token in this repository.

## GitHub Pages deployment

1. In this repository, open Settings → Pages.
2. Select **GitHub Actions** as the build and deployment source.
3. Open Actions → Publish Snapcircle → Run workflow (or push a new commit to main).
4. The workflow uploads only the site/ directory. It does not publish database scripts or tests as website assets.
5. Open the URL returned by the successful GitHub Pages deployment.

All routes use URL fragments and all assets use relative paths, so this works under /snapcircle/ as well as a custom domain. GitHub Pages serves the frontend without a running laptop or Node process.

GitHub Pages availability for a private repository depends on the GitHub plan. Preserve repository visibility; if Pages is unavailable, the owner can select a supported plan or explicitly choose to make the code repository public. Photos and account data live in the private Supabase backend, not the Git repository.

## Required login URL configuration

After GitHub Pages returns the production URL, in Supabase:
1. Open Authentication → URL Configuration.
2. Set Site URL to the complete Pages URL, including /snapcircle/ and its trailing slash.
3. Add that same URL to Redirect URLs.
4. Add http://127.0.0.1:5180/ only if you want to test email confirmation or password recovery locally.

This step is required for confirmation emails and password reset links to return to the right site. Email delivery depends on the project's Auth email configuration and its limits.

## Use with your friend

1. Both people create accounts and confirm their emails.
2. One person opens My circle and copies the link and invite code.
3. The other signs in and enters that code under My circle.
4. Photos, snaps and albums now appear in the same circle. Profile colors and titles remain personal.
5. Joining another circle changes your active view; earlier uploads stay in the original circle.

## Local preview

Install Node.js, then run:

    node preview.mjs

Open http://127.0.0.1:5180/ and choose Explore the preview. No build or dependency installation is needed.

## Validation

- JavaScript syntax checks passed.
- Browser checked: sign-in layout, responsive preview, tab navigation, search, favorites, album creation, upload with album assignment, snap upload and points, reward redemption and theme equip.
- supabase/verify.sql checks circle isolation, joining, server scoring, album creation, redemption, equip, direct mutation protection and ownership. It wraps synthetic fixtures in a transaction and rolls everything back.
- Production sign-in with a real email and email redirects still need an end-to-end check after the final production URL is configured.

The database uses authenticated SECURITY DEFINER RPCs intentionally to validate ownership, membership, spending and point amounts. Each function fixes its search_path and derives identity from auth.uid(). Direct client mutation of scores or inventory is blocked by row policies.

The Supabase free plan was quoted at $0/month at creation. Provider availability, storage/email quotas and free-project inactivity policies still apply; this is not an uptime guarantee.

## Files

- site/: deployable frontend
- supabase/setup.sql: initial schema already applied to the configured project; do not rerun on that project
- supabase/verify.sql: transaction-only backend verification
- .github/workflows/pages.yml: automatic deployment on main
- preview.mjs: dependency-free local server

ROTARACT MONTHLY QUIZ - UPGRADE

Files:
- index.html   participant page
- admin.html   existing admin page with analytics + Hall of Fame
- results.html past results / result card page
- verify.html  QR verification page
- quiz_upgrade.sql additive SQL only

SQL:
1. Run quiz_upgrade.sql in Supabase SQL Editor.
2. Keep your existing Auth, user_roles, tables and existing RPCs unchanged.
3. Deploy all HTML files together. Put verify.html beside index.html/results.html.

Added:
- Quiz Champion / Runner-up / 3rd Place badges
- Fastest Finisher badge
- Yearly Champion badge when current yearly winner matches
- Result card download blocked until quiz end time
- Review always shows chosen answer + correct answer + wrong/correct status after submission
- Result card QR verification
- Hall of Fame
- Question Analytics
- Participation Trend
- Certificate verification page

Important: Existing login/auth flow was not changed.

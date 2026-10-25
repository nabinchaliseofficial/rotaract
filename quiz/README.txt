ROTARACT QUIZ v2
=================

FILES
-----
1. index.html
   - Single participant page
   - Inline registration
   - QR link support: index.html?quiz=QUIZ_UUID
   - Before quiz: NOT LIVE
   - During quiz: registration -> direct quiz
   - Late join gets only remaining event time
   - Server-time-synchronised timer
   - One-question-at-a-time mobile UI
   - Selecting an option automatically opens next question
   - Automatic submit when time ends
   - No negative marking
   - Equal score -> faster completion wins
   - Live Supabase Realtime leaderboard

2. admin.html
   - Supabase Auth login
   - user_roles role=admin and status=active check
   - Create quiz/date/start/end/duration
   - Add/edit questions
   - Publish/unpublish
   - Participant list
   - Results/winners
   - Per-quiz social media banner
   - Banner PNG download
   - QR PNG download

3. quiz.sql
   - quiz_quizzes
   - quiz_questions
   - quiz_participants
   - quiz_attempts
   - quiz_leaderboard
   - RLS
   - server time RPC
   - inline registration RPC
   - start-attempt RPC
   - scoring/auto-submit RPC
   - public leaderboard RPC
   - Realtime publication setup

SUPABASE SETUP
--------------
1. Open Supabase SQL Editor.
2. Run ALL of quiz.sql.
3. Ensure the admin Auth account exists.
4. Ensure that Auth user's UUID exists in public.user_roles:
   role='admin'
   status='active'
5. Host index.html and admin.html at the same web path.
6. Open admin.html and create/publish the quiz.
7. Generate the social banner + QR.
8. QR opens index.html?quiz=<quiz id>.
9. QR scanned before/after scheduled time shows NOT LIVE.
10. QR scanned during the scheduled time opens inline registration, then quiz.

IMPORTANT SECURITY
------------------
- Only the Supabase publishable key is in HTML.
- Never put service_role/secret keys in frontend files.
- Correct answers are only exposed by quiz_questions while the quiz is live, because participants need them? Actually the current design fetches question options and correct_option is intentionally excluded from SELECT.
- Scoring occurs in SECURITY DEFINER PostgreSQL function.
- quiz_attempts is not public-readable; only quiz_leaderboard is public-readable.
- Realtime subscribes to quiz_leaderboard, which contains safe public result fields only.

REALTIME
--------
The SQL adds public.quiz_leaderboard to supabase_realtime.
index.html subscribes to INSERT/UPDATE/DELETE and refreshes the leaderboard automatically.

SERVER TIME
-----------
The timer is based on a server-time RPC offset and, most importantly, PostgreSQL validates the quiz end time during submission. Changing the phone/PC clock does not grant extra quiz time.

BANNER
------
Admin -> Banner + QR -> select quiz -> Download Banner PNG.
The banner includes title, date, time, duration, QR, and a clear call-to-action suitable for social media.

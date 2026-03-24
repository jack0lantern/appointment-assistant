# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Demo accounts (see README):
#   therapist@demo.health / demo123
#   therapist2@demo.health / demo123
#   client@demo.health / demo123
#   jordan.kim@demo.health / demo123  (Jordan — always routes as new patient for demo)
#   maya.patel@demo.health, chris.wong@demo.health, etc. / demo123

# ─── Alex Rivera demo sessions ────────────────────────────────────────────────
# Seeded below the user/therapist block so IDs are always available.
# Guard at the bottom ensures idempotency.
# ──────────────────────────────────────────────────────────────────────────────

unless User.exists?(email: "therapist@demo.health")
  therapist = User.create!(
    email: "therapist@demo.health",
    name: "Dr. Sarah Chen",
    role: "therapist",
    password: "demo123"
  )

  client_user = User.create!(
    email: "client@demo.health",
    name: "Alex Rivera",
    role: "client",
    password: "demo123"
  )

  tp = Therapist.create!(
    user_id: therapist.id,
    license_type: "LCSW",
    specialties: ["anxiety", "depression", "CBT"],
    preferences: {},
    slug: "dr-sarah-chen"
  )

  Client.create!(
    user_id: client_user.id,
    therapist_id: tp.id,
    name: "Alex Rivera"
  )
end

therapist_profile = Therapist.joins(:user).find_by!(users: { email: "therapist@demo.health" })
alex_client       = Client.joins(:user).find_by!(users: { email: "client@demo.health" })

# ─── Alex Rivera: 5 sessions with transcripts, summaries, treatment plan ──────
unless Session.exists?(client_id: alex_client.id)

  SPEAKER_MAP = { "T" => "Dr. Sarah Chen", "C" => "Alex Rivera" }.freeze

  # Helper: build utterances array from interleaved [speaker, text] pairs
  def build_utterances(pairs)
    t = 0
    pairs.map do |(speaker, text)|
      words = text.split.length
      u = { "speaker" => speaker, "text" => text, "start_time" => t }
      t += (words * 0.4).ceil  # rough seconds
      u
    end
  end

  # ── Session 1 — Feb 3 2026 — Initial Assessment ───────────────────────────
  s1_transcript_pairs = [
    ["T", "Hi Alex, welcome. I'm glad you made it in today. How are you feeling right now?"],
    ["C", "Honestly, a little nervous. I've never done therapy before and I wasn't sure what to expect."],
    ["T", "That's completely understandable, and it's actually pretty common for a first session. There's nothing to perform here — I just want to get to know you and understand what's been going on. Can you start by telling me a bit about what brought you in?"],
    ["C", "Sure. I've just been feeling really overwhelmed lately. Work is a lot — I'm a software engineer and we just shipped a big product update, and I feel like I can never really switch off. I lie awake at night going over things, replaying conversations, worrying about what might go wrong tomorrow."],
    ["T", "That sounds exhausting. How long has this been going on?"],
    ["C", "Maybe six months? It got worse after we had a big reorganization at work. I got a new manager and the whole team dynamic shifted. I feel like I'm being watched all the time, like I might say the wrong thing in a meeting."],
    ["T", "So there's a social component to this too — not just worry about tasks, but worry about how you're perceived?"],
    ["C", "Yeah, definitely. I'll spend like an hour after a meeting going over what I said, wondering if I came across as competent or if people think I'm an idiot."],
    ["T", "That's a pattern called post-event processing. It's really common in people who experience anxiety, especially social anxiety. The mind keeps reviewing things looking for threats, even though the event is over. Does that resonate?"],
    ["C", "Yeah, that's exactly it. I hadn't heard that term before but that's what it feels like."],
    ["T", "Let me ask you about sleep. You mentioned lying awake — can you describe what a typical night looks like?"],
    ["C", "I usually fall asleep okay, but I wake up around two or three in the morning and then my brain just starts. I'll think about something embarrassing from years ago, or I'll start making a mental list of everything I haven't done at work. It's hard to get back to sleep after that."],
    ["T", "And how is your mood during the day? Do you feel low as well as anxious, or is it mostly the anxiety?"],
    ["C", "Mostly anxious. Though sometimes I feel pretty flat, like things that used to be fun — I used to play guitar, I haven't touched it in months. I don't know if that's depression or just being too busy and tired."],
    ["T", "It could be both, and we'll explore that together. I want to be careful not to jump ahead, but what you're describing — the persistent worry, the sleep disruption, the social self-monitoring, and losing interest in activities you used to enjoy — those are things we can absolutely work on. I use a lot of cognitive behavioral therapy, CBT, which has very strong evidence for exactly what you're describing. Does that sound okay?"],
    ["C", "Yeah, I've heard of CBT. I'm open to it."],
    ["T", "Great. For this week, before we get into any techniques, I'd like you to keep a simple worry journal. Just a notes app or a piece of paper — whenever you notice yourself worrying, jot down what triggered it, what you were worried about, and how intense it felt on a scale of one to ten. It's not about fixing anything yet, just noticing. Can you try that?"],
    ["C", "Yeah, I can do that."],
    ["T", "Perfect. I think we've covered a lot of ground for a first session. How are you feeling now compared to when you walked in?"],
    ["C", "Actually a bit better. It helps to say it out loud, I think. It felt like this nameless thing and now it has a little more shape."],
    ["T", "That's a great observation. We'll keep giving it shape. Same time next week?"],
    ["C", "Yes, sounds good. Thank you."]
  ]

  s1_content = s1_transcript_pairs.map { |(spk, txt)| "#{spk == 'T' ? 'Therapist' : 'Client'}: #{txt}" }.join("\n")

  sess1 = Session.create!(
    therapist_id:     therapist_profile.id,
    client_id:        alex_client.id,
    session_date:     Time.zone.parse("2026-02-03 10:00:00"),
    session_number:   1,
    duration_minutes: 55,
    status:           "completed",
    session_type:     "uploaded"
  )

  Transcript.create!(
    session_id:   sess1.id,
    content:      s1_content,
    source_type:  "uploaded",
    word_count:   s1_content.split.length,
    utterances:   build_utterances(s1_transcript_pairs),
    speaker_map:  SPEAKER_MAP
  )

  SessionSummary.create!(
    session_id:       sess1.id,
    therapist_summary: "Alex Rivera presented for an initial assessment reporting generalized anxiety with a social component, onset approximately 6 months ago coinciding with a workplace reorganization. Key presenting concerns: persistent worry and post-event processing after work meetings, sleep-maintenance insomnia (waking 2–3 AM with ruminative thinking), and anhedonia (stopped playing guitar). No safety concerns. Rapport was good; client appeared engaged and reflective. Psychoeducation on post-event processing provided. Modality: CBT. Homework assigned: worry journal (trigger, content, intensity 1–10).",
    client_summary:    "Today we talked about what's been making you anxious — especially the worry that seems to ramp up after work meetings, and the sleep disruptions at night. We gave a name to the pattern of replaying conversations after they happen (post-event processing) and talked about how CBT can help. Your first homework is to keep a worry journal: whenever you notice worry, write down what triggered it, what you were worried about, and how intense it felt (1–10). No fixing needed yet, just noticing.",
    key_themes:        ["generalized anxiety", "social anxiety", "post-event processing", "sleep disruption", "anhedonia", "workplace stress", "CBT introduction"]
  )

  # Treatment plan created after session 1
  tplan = TreatmentPlan.create!(
    client_id:    alex_client.id,
    therapist_id: therapist_profile.id,
    status:       "active"
  )

  tpv1 = TreatmentPlanVersion.create!(
    treatment_plan_id: tplan.id,
    version_number:    1,
    session_id:        sess1.id,
    source:            "ai_generated",
    change_summary:    "Initial treatment plan following intake assessment (seed / demo).",
    therapist_content: {
      "presenting_concerns" => [
        "Generalized anxiety with social features; onset ~6 months after workplace reorganization",
        "Post-event processing after meetings; sleep-maintenance insomnia (waking 2–3 AM with rumination)",
        "Reduced engagement in valued activities (e.g., guitar)"
      ],
      "goals" => [
        { "description" => "Reduce frequency and intensity of worry episodes", "modality" => "CBT", "timeframe" => "8–12 weeks" },
        { "description" => "Improve sleep continuity", "modality" => "CBT / behavioral", "timeframe" => "ongoing" },
        { "description" => "Re-engage with valued activities (guitar)", "modality" => "Behavioral activation", "timeframe" => "4–8 weeks" },
        { "description" => "Develop skills to manage post-event rumination", "modality" => "CBT", "timeframe" => "8–12 weeks" }
      ],
      "interventions" => [
        { "name" => "Psychoeducation", "modality" => "CBT", "description" => "Anxiety model, post-event processing, overview of CBT" },
        { "name" => "Self-monitoring", "modality" => "CBT", "description" => "Worry journal (trigger, content, intensity 1–10)" },
        { "name" => "Cognitive restructuring", "modality" => "CBT", "description" => "Thought records and examining evidence" },
        { "name" => "Behavioral activation", "modality" => "BA", "description" => "Scheduling pleasant and mastery activities" },
        { "name" => "Sleep skills", "modality" => "CBT-I (intro)", "description" => "Sleep hygiene and deferring worry overnight" },
        { "name" => "Graduated exposure", "modality" => "CBT", "description" => "Planned approach to feared social work situations" }
      ],
      "homework" => [
        "Worry journal: when worry appears, note trigger, worry content, and intensity (1–10); observation only this week"
      ],
      "strengths" => [
        "Strong insight and motivation",
        "Articulate; engaged in first session",
        "Able to link symptoms to work context"
      ],
      "diagnosis_considerations" => [
        "Generalized Anxiety Disorder (provisional); rule out Social Anxiety Disorder"
      ]
    },
    client_content: {
      "what_we_talked_about" =>
        "We mapped worry that spikes after work meetings, waking up at night with racing thoughts, and losing touch with things you used to enjoy (like guitar). We named the pattern of replaying conversations after they happen (post-event processing) and talked about how CBT can help.",
      "your_goals" => [
        "Feel more in control of worry day to day",
        "Sleep through the night more often",
        "Get back to guitar and activities that matter to you",
        "Feel steadier in work meetings"
      ],
      "things_to_try" => [
        "Use a simple worry journal when worry shows up (no fixing yet—just notice)",
        "Note what triggered the worry and how strong it felt (1–10)"
      ],
      "your_strengths" => [
        "You explain your experience clearly",
        "You're open to trying CBT tools",
        "You already see how work stress connects to symptoms"
      ],
      "next_steps" => ["Bring your worry journal notes to the next session"]
    }
  )

  tplan.update!(current_version_id: tpv1.id)

  HomeworkItem.create!(
    treatment_plan_version_id: tpv1.id,
    client_id:                 alex_client.id,
    description:               "Keep a worry journal this week. Whenever you notice worry, write down: (1) what triggered it, (2) what you were worried about, (3) intensity 1–10. Use notes app or paper — no fixing yet, just noticing.",
    completed:                 true,
    completed_at:              Time.zone.parse("2026-02-09 20:00:00")
  )

  # ── Session 2 — Feb 10 2026 — CBT & Thought Records ────────────────────────
  s2_transcript_pairs = [
    ["T", "Welcome back, Alex. How was your week? Did you have a chance to try the worry journal?"],
    ["C", "I did, yeah. It was actually kind of eye-opening. I ended up writing in it way more than I expected — like six or seven entries just in the first four days."],
    ["T", "That's really useful data. What did you notice?"],
    ["C", "Most of my worries are about work — like whether I did something well enough, or whether I'm going to mess up a presentation. The intensity was mostly in the six to eight range. There were a couple at nine."],
    ["T", "What were the nines about?"],
    ["C", "One was right before a sprint planning meeting. I was convinced I was going to say something dumb in front of the new manager and that he'd think I didn't know what I was doing."],
    ["T", "And what actually happened?"],
    ["C", "It was fine. I mean, I stumbled over my words a bit at one point, but nobody noticed, or if they did they didn't say anything."],
    ["T", "That's really important to sit with for a moment. You predicted a catastrophe — humiliation in front of your manager — and what actually happened was: you stumbled a little and no one reacted. How did your anxious mind reconcile that afterward?"],
    ["C", "I mean, I was relieved in the moment. But then I started thinking maybe they were just being polite, or they noticed but didn't want to embarrass me."],
    ["T", "There it is. That's a cognitive distortion called 'disqualifying the positive' — when evidence that contradicts our fear gets explained away so the fear can survive. The anxiety always finds a loophole. Does that sound right?"],
    ["C", "Yeah, that's exactly what I do. It's like the anxiety is a lawyer and it always finds a counterargument."],
    ["T", "I love that metaphor — the anxiety lawyer. Let's start working with thought records. A thought record is a structured way to examine anxious thoughts and test whether they hold up to scrutiny. It has five parts: the situation, the emotion and its intensity, the automatic thought, the evidence for and against it, and then a more balanced thought. Let me walk you through the sprint planning example using that structure."],
    ["C", "Okay."],
    ["T", "Situation: sprint planning meeting with new manager. Emotion: anxiety, eight out of ten. Automatic thought: 'I'm going to say something dumb and he'll think I'm incompetent.' Now — evidence that supports this thought?"],
    ["C", "I've stumbled over words before in meetings. I sometimes forget the exact details of a ticket when put on the spot."],
    ["T", "Okay. Evidence against?"],
    ["C", "I've been on this team for two years. I've shipped a lot of features. My previous manager gave me a strong performance review. In this specific meeting, I did actually stumble but no one reacted negatively."],
    ["T", "So when you lay it out like that — is 'he'll think I'm incompetent' really the most accurate prediction?"],
    ["C", "When you put it that way, no. I mean, stumbling once in a meeting doesn't define competence."],
    ["T", "A more balanced thought might be something like: 'I might be imperfect in this meeting, and that's okay — one stumble doesn't determine how I'm perceived overall.' How does that land?"],
    ["C", "That actually feels a lot more true. It's less dramatic."],
    ["T", "The goal isn't to replace anxiety with blind optimism — it's to replace distorted thinking with something accurate. Can you try completing a thought record on your own this week whenever you notice a high-intensity worry?"],
    ["C", "Yeah, I'll try. Do I need a specific format?"],
    ["T", "I'll send you a simple template. Five columns: situation, emotion + intensity, automatic thought, evidence for and against, balanced thought. Just one entry is enough — pick the anxiety that bothered you most."],
    ["C", "Okay, that's manageable."],
    ["T", "How are you sleeping?"],
    ["C", "About the same. Still waking up around two-thirty. Sometimes I can get back to sleep in thirty minutes, sometimes it's an hour."],
    ["T", "We'll address sleep more directly soon — there's a whole set of techniques for that. For now, if you wake up and start ruminating, try writing the worry down with a note that says 'I'll deal with this tomorrow.' It gives the brain permission to let it go for the night."],
    ["C", "I'll try that tonight actually."],
    ["T", "Good. See you next week."]
  ]

  s2_content = s2_transcript_pairs.map { |(spk, txt)| "#{spk == 'T' ? 'Therapist' : 'Client'}: #{txt}" }.join("\n")

  sess2 = Session.create!(
    therapist_id:     therapist_profile.id,
    client_id:        alex_client.id,
    session_date:     Time.zone.parse("2026-02-10 10:00:00"),
    session_number:   2,
    duration_minutes: 50,
    status:           "completed",
    session_type:     "uploaded"
  )

  Transcript.create!(
    session_id:   sess2.id,
    content:      s2_content,
    source_type:  "uploaded",
    word_count:   s2_content.split.length,
    utterances:   build_utterances(s2_transcript_pairs),
    speaker_map:  SPEAKER_MAP
  )

  SessionSummary.create!(
    session_id:        sess2.id,
    therapist_summary: "Alex returned with completed worry journal — 6–7 entries, intensity 6–9, predominantly work-focused. Reviewed sprint planning example: clear post-event processing pattern with disqualification of positive evidence. Introduced thought records (5-column format). Client demonstrated good initial grasp of cognitive restructuring. Psychoeducation on cognitive distortions (disqualifying the positive). Sleep unchanged. Interim sleep suggestion given: write worry down with permission-to-defer note at 2 AM waking.",
    client_summary:    "Great work completing the worry journal! We looked at a specific moment — the sprint planning meeting — and used it to practice a thought record. You identified your automatic thought ('he'll think I'm incompetent'), gathered evidence for and against it, and arrived at a more balanced take. This week, complete one thought record for your biggest worry. I'll send you the 5-column template.",
    key_themes:        ["worry journal review", "cognitive distortions", "disqualifying the positive", "thought records", "CBT", "sleep maintenance"]
  )

  HomeworkItem.create!(
    treatment_plan_version_id: tpv1.id,
    client_id:                 alex_client.id,
    description:               "Complete one thought record (5-column format) for your biggest worry this week: situation → emotion + intensity → automatic thought → evidence for/against → balanced thought.",
    completed:                 true,
    completed_at:              Time.zone.parse("2026-02-16 19:30:00")
  )

  HomeworkItem.create!(
    treatment_plan_version_id: tpv1.id,
    client_id:                 alex_client.id,
    description:               "Sleep tip: if you wake at 2–3 AM and start ruminating, write the worry down with a note 'I'll deal with this tomorrow' to give your brain permission to let it go.",
    completed:                 true,
    completed_at:              Time.zone.parse("2026-02-14 08:00:00")
  )

  # ── Session 3 — Feb 17 2026 — Behavioral Activation & Avoidance ─────────────
  s3_transcript_pairs = [
    ["T", "Hi Alex. How did the thought record go?"],
    ["C", "I did it. It took me about twenty minutes — I kept second-guessing whether I was filling it in right — but I did it."],
    ["T", "Let's hear it. What situation did you pick?"],
    ["C", "My team lead asked me to present a technical summary to the wider engineering group next Friday. Just like a ten-minute update on what we built. And I immediately went into full panic mode."],
    ["T", "What was the automatic thought?"],
    ["C", "Something like — 'Everyone's going to realize I don't actually understand this as deeply as they think I do. I'm going to get asked a question I can't answer and freeze up, and then everyone will know I'm a fraud.'"],
    ["T", "Impostor syndrome shows up right there. What evidence did you find against that thought?"],
    ["C", "I built the feature. I know it well. I've explained it clearly to teammates one-on-one. I've given internal presentations before and they went fine."],
    ["T", "And your balanced thought?"],
    ["C", "Something like — 'I know this work well enough to present it. I might not have every answer, and that's okay — no one expects me to know everything.'"],
    ["T", "That's a really solid thought record, Alex. How did writing it out affect your anxiety about the presentation?"],
    ["C", "It went from like an eight to maybe a five. Which was huge. I still feel nervous about it, but it's not this crushing thing anymore."],
    ["T", "That reduction from eight to five is meaningful. Notice that the goal wasn't to get to zero — some nervousness before a presentation is actually useful, it sharpens your focus. We want to get it to a manageable level. I want to talk today about something related: avoidance. What would you have done about the presentation if we hadn't been working on this?"],
    ["C", "Honestly? I might have tried to get out of it. Told my team lead I was too busy or asked someone else to do it."],
    ["T", "And if you'd avoided it, what would have happened to the anxiety?"],
    ["C", "It would have gone away immediately. But then I'd probably feel guilty, and the same situation would come up again."],
    ["T", "Exactly. Avoidance is the anxiety's best friend. It provides short-term relief but long-term it teaches the brain that the situation really was dangerous, which makes the fear stronger. Doing the presentation — even imperfectly — will actually train your brain that it's survivable. That's exposure, and it's one of the most powerful tools we have."],
    ["C", "So I should do the presentation."],
    ["T", "I think you should do the presentation. And I'd like to help you prepare in a way that doesn't turn into perfectionism. How much time have you spent thinking about it so far?"],
    ["C", "Probably three or four hours, and I haven't even started the slides yet. Mostly just worrying."],
    ["T", "Let's agree: one hour of focused prep, slides done, one dry run. That's it. The rest is just the anxiety trying to make you feel like more prep will make it perfectly safe. There's no amount of prep that removes the possibility of being asked a hard question."],
    ["C", "That's... actually kind of freeing. One hour."],
    ["T", "I also want to introduce behavioral activation this week. You mentioned you stopped playing guitar. What else have you dropped in the last six months?"],
    ["C", "Running. I used to run three times a week, now maybe once. Going out with friends — I've been saying no to social things a lot. Just cooking for myself instead of ordering out, which sounds small but even that feels like an effort."],
    ["T", "Depression and anxiety both create this narrowing effect on life. You stop doing things that used to give you energy, which means you have less energy, which makes it harder to do anything. Behavioral activation is about deliberately scheduling activities that give you a sense of pleasure or accomplishment, even when you don't feel like it. The motivation often comes after the action, not before. Can you schedule two small activities this week — something pleasant or meaningful?"],
    ["C", "I could try to pick up the guitar for like fifteen minutes. And maybe go for a short run."],
    ["T", "Perfect. Not a marathon, not a performance — just fifteen minutes and a short run. And I want you to rate your mood before and after each one, just mentally. I suspect you'll notice a difference."],
    ["C", "I also want to mention — the sleep trick worked. A couple of times I wrote down the worry and I was able to get back to sleep faster. Not always, but a few times."],
    ["T", "That's real progress. The brain is learning that it doesn't have to solve everything at 2 AM. We'll build on that."]
  ]

  s3_content = s3_transcript_pairs.map { |(spk, txt)| "#{spk == 'T' ? 'Therapist' : 'Client'}: #{txt}" }.join("\n")

  sess3 = Session.create!(
    therapist_id:     therapist_profile.id,
    client_id:        alex_client.id,
    session_date:     Time.zone.parse("2026-02-17 10:00:00"),
    session_number:   3,
    duration_minutes: 50,
    status:           "completed",
    session_type:     "uploaded"
  )

  Transcript.create!(
    session_id:   sess3.id,
    content:      s3_content,
    source_type:  "uploaded",
    word_count:   s3_content.split.length,
    utterances:   build_utterances(s3_transcript_pairs),
    speaker_map:  SPEAKER_MAP
  )

  SessionSummary.create!(
    session_id:        sess3.id,
    therapist_summary: "Alex completed thought record independently. Presenting situation: upcoming technical presentation to wider eng group. Thought record well executed — anxiety reduced from 8→5 after restructuring. Impostor syndrome themes prominent. Psychoeducation on avoidance maintenance of anxiety. Discussed behavioral activation: client identified guitar and running as dropped activities. Homework: do the presentation; schedule guitar (15 min) and short run this week; rate mood before/after. Sleep tip showing early results — client successfully deferred worry on multiple nights.",
    client_summary:    "You did a great thought record — anxiety about the presentation went from an 8 to a 5 just by examining the evidence. We talked about avoidance and how skipping the presentation would make future anxiety worse. You're going to give the presentation with one hour of prep and one dry run — no more. We also talked about behavioral activation: getting back to small things you used to enjoy. This week: play guitar for 15 minutes and go for a short run. Notice how your mood feels before and after.",
    key_themes:        ["thought records", "impostor syndrome", "avoidance", "exposure", "behavioral activation", "guitar", "running", "sleep improvement"]
  )

  HomeworkItem.create!(
    treatment_plan_version_id: tpv1.id,
    client_id:                 alex_client.id,
    description:               "Give the technical presentation to the engineering group on Friday. Prep with one focused hour + one dry run — no more. Practice tolerating imperfection.",
    completed:                 true,
    completed_at:              Time.zone.parse("2026-02-21 15:00:00")
  )

  HomeworkItem.create!(
    treatment_plan_version_id: tpv1.id,
    client_id:                 alex_client.id,
    description:               "Behavioral activation: (1) play guitar for 15 minutes at least once; (2) go for a short run at least once. Rate your mood before and after each one.",
    completed:                 true,
    completed_at:              Time.zone.parse("2026-02-20 18:00:00")
  )

  # ── Session 4 — Feb 24 2026 — Panic Attack & Grounding ──────────────────────
  s4_transcript_pairs = [
    ["T", "Hi Alex. How did the week go? You mentioned in your message that something happened."],
    ["C", "Yeah. So the presentation went well — actually really well, I got good feedback — but then two days later I had what I think was a panic attack at work. It came out of nowhere."],
    ["T", "I'm glad you reached out. Can you walk me through what happened?"],
    ["C", "It was Wednesday afternoon. I was in a one-on-one with my new manager, just a regular check-in. And he asked me something about my career goals — like, totally normal question — and something just switched. My heart started pounding, I felt like I couldn't breathe properly, my hands went kind of tingly. I thought something was physically wrong with me. I had to excuse myself and go to the bathroom."],
    ["T", "That sounds really frightening. How long did it last?"],
    ["C", "Maybe ten minutes? Fifteen? It felt like forever. Once I was in the bathroom and sitting down it started to ease off."],
    ["T", "What you're describing is a panic attack. The physical sensations — racing heart, difficulty breathing, tingling — are caused by your nervous system activating the fight-or-flight response. It's completely non-dangerous physically, even though it feels terrifying. The sensation of not being able to breathe is actually caused by over-breathing, which paradoxically makes you feel like you need more air. Does knowing that help at all?"],
    ["C", "A little. I was genuinely convinced something was medically wrong."],
    ["T", "That fear of a physical catastrophe is a core feature of panic. The panic attack feeds on itself — you feel sensations, you interpret them as dangerous, you get more anxious, the sensations get worse. Interrupting that loop early is key. What did you do in the bathroom to calm down?"],
    ["C", "I tried to slow my breathing. And I splashed cold water on my face, which actually helped a lot."],
    ["T", "Cold water is a legitimate physiological technique — it activates the dive reflex and slows the heart rate. That was a good instinct. I want to teach you a more structured grounding technique for these moments — it's called 5-4-3-2-1 and it pulls your attention from the internal sensations back to the external world. You name five things you can see, four you can touch, three you can hear, two you can smell, one you can taste. It interrupts the panic loop by re-engaging your senses."],
    ["C", "I've heard of that. I never thought to actually use it."],
    ["T", "Practice it now when you're calm, so it's automatic when you need it. Let's do it together right now — what are five things you can see in this room?"],
    ["C", "Uh, the plant in the corner, your desk lamp, the framed picture on the wall, my own hands, the window."],
    ["T", "Good. Four things you can physically feel right now?"],
    ["C", "My back against the chair, my feet on the floor, the fabric of my jeans on my legs, the weight of my phone in my pocket."],
    ["T", "Exactly. How do you feel doing that?"],
    ["C", "More grounded. It's hard to think about the panic when I'm focusing on these things."],
    ["T", "That's the mechanism. Now — let's talk about what triggered the panic in that meeting. You said he asked about career goals?"],
    ["C", "Yeah. I think it's because I don't really know what my career goals are, and the idea of saying that out loud to my manager felt like exposing a huge weakness. Like if I don't have ambition and a plan, maybe I don't deserve to be there."],
    ["T", "There's a lot to unpack there. There's a core belief that deserving your position is contingent on having a clear trajectory and demonstrating ambition. A lot of high-performing people in tech carry that belief. It becomes a vulnerability. We should look at that belief more carefully over the coming weeks."],
    ["C", "I've never thought about it in those terms but yeah, that resonates."],
    ["T", "The presentation going well — how did that feel?"],
    ["C", "Really good, actually. People asked questions and I handled them. One person said it was the clearest explanation of the feature they'd heard. That felt amazing."],
    ["T", "Hold onto that. That's real evidence. I want to update your treatment plan a bit — let's add grounding techniques and start thinking about the deeper belief work. For homework this week, I want you to practice the 5-4-3-2-1 technique once a day when you're calm, and also continue with your thought records."],
    ["C", "Okay, I can do that."],
    ["T", "Also — how did the guitar and the run go?"],
    ["C", "I played for like twenty minutes actually, I got into it. And I ran twice. The mood rating thing was interesting — I was definitely in a better mood after both of them."],
    ["T", "That's the behavioral activation working. Keep going with both of those."]
  ]

  s4_content = s4_transcript_pairs.map { |(spk, txt)| "#{spk == 'T' ? 'Therapist' : 'Client'}: #{txt}" }.join("\n")

  sess4 = Session.create!(
    therapist_id:     therapist_profile.id,
    client_id:        alex_client.id,
    session_date:     Time.zone.parse("2026-02-24 10:00:00"),
    session_number:   4,
    duration_minutes: 50,
    status:           "completed",
    session_type:     "uploaded"
  )

  Transcript.create!(
    session_id:   sess4.id,
    content:      s4_content,
    source_type:  "uploaded",
    word_count:   s4_content.split.length,
    utterances:   build_utterances(s4_transcript_pairs),
    speaker_map:  SPEAKER_MAP
  )

  SessionSummary.create!(
    session_id:        sess4.id,
    therapist_summary: "Alex had first documented panic attack (Wed Feb 19) during 1:1 with new manager, triggered by career-goals question. Duration ~10–15 min. Instinctively used controlled breathing + cold water — effective. Presentation prior (Fri Feb 17) went very well — positive feedback, handled Q&A. Psychoeducation on panic cycle and fight-or-flight. Introduced 5-4-3-2-1 grounding; practiced in session. Identified underlying core belief: 'I must demonstrate ambition and have a clear plan to deserve my position.' Behavioral activation continuing well — guitar 20 min, ran twice, positive mood shift noted. Treatment plan updated to add grounding and core belief work.",
    client_summary:    "You had a panic attack this week — scary, but you handled it well (breathing + cold water). We talked about what's happening physiologically during panic and why it feels worse than it is. You learned the 5-4-3-2-1 grounding technique to interrupt the panic loop — practice it once a day this week even when calm. The presentation went really well — hold onto that. Your guitar and running habits are paying off mood-wise. Keep going with both.",
    key_themes:        ["panic attack", "fight-or-flight", "grounding", "5-4-3-2-1", "core beliefs", "deserving your position", "behavioral activation progress", "presentation success"]
  )

  # Version 2 of treatment plan — after session 4
  tpv2 = TreatmentPlanVersion.create!(
    treatment_plan_id: tplan.id,
    version_number:    2,
    session_id:        sess4.id,
    source:            "ai_generated",
    change_summary:    "Updated after first panic attack: grounding, core belief work, continued CBT (seed / demo).",
    therapist_content: {
      "presenting_concerns" => [
        "Generalized anxiety with social features; first panic attack documented (Feb 19) during 1:1",
        "Core belief surfaced: self-worth tied to demonstrating ambition and clear career trajectory",
        "Strong response to thought records, behavioral activation, and sleep deferral strategies"
      ],
      "goals" => [
        { "description" => "Reduce panic symptoms using early skills (grounding, psychoeducation)", "modality" => "CBT", "timeframe" => "4–6 weeks" },
        { "description" => "Continue thought records for high-intensity worry", "modality" => "CBT", "timeframe" => "ongoing" },
        { "description" => "Examine and revise core belief about deserving one's role", "modality" => "CBT / schema-informed", "timeframe" => "8+ weeks" },
        { "description" => "Sustain behavioral activation (guitar, running, social engagement)", "modality" => "BA", "timeframe" => "ongoing" },
        { "description" => "Improve sleep continuity", "modality" => "CBT-I (intro)", "timeframe" => "ongoing" }
      ],
      "interventions" => [
        { "name" => "Grounding", "modality" => "CBT", "description" => "5-4-3-2-1 sensory grounding; practice daily when calm" },
        { "name" => "Panic psychoeducation", "modality" => "CBT", "description" => "Fight-or-flight loop, benign nature of sensations" },
        { "name" => "Thought records", "modality" => "CBT", "description" => "Evidence for/against; balanced thoughts (ongoing)" },
        { "name" => "Core belief work", "modality" => "CBT", "description" => "Identify and test beliefs about competence and belonging" },
        { "name" => "Behavioral activation", "modality" => "BA", "description" => "Pleasure/mastery scheduling (guitar, running)" },
        { "name" => "Sleep skills", "modality" => "CBT-I (intro)", "description" => "Defer worry overnight; stimulus control as needed" }
      ],
      "homework" => [
        "Practice 5-4-3-2-1 grounding once daily when calm",
        "Complete one thought record for any worry rated 7+",
        "Continue guitar and running at least once each this week"
      ],
      "strengths" => [
        "Excellent homework follow-through",
        "Presentation success with positive feedback",
        "Uses behavioral activation with observable mood benefit"
      ],
      "diagnosis_considerations" => [
        "Panic Disorder (provisional, single episode); Generalized Anxiety Disorder; Social Anxiety features"
      ]
    },
    client_content: {
      "what_we_talked_about" =>
        "You experienced a panic attack at work—we covered what happens in your body and why it feels scary but is not dangerous. You learned 5-4-3-2-1 grounding. We also connected panic to worries about career goals and feeling like you have to prove you belong.",
      "your_goals" => [
        "Catch panic early and use grounding before it spirals",
        "Question the story that you need a perfect five-year plan to deserve your job",
        "Keep guitar and running going—they're helping your mood",
        "Stay steady when tough questions come up at work"
      ],
      "things_to_try" => [
        "Daily grounding practice (even when you feel fine)",
        "One full thought record on your toughest worry this week",
        "Keep up short music and movement breaks you already started"
      ],
      "your_strengths" => [
        "You reached out quickly after the panic attack",
        "Your presentation went well—you handled questions",
        "You're building real coping skills, not just coping day-to-day"
      ],
      "next_steps" => ["Report back on grounding and thought records next session"]
    }
  )

  tplan.update!(current_version_id: tpv2.id)

  HomeworkItem.create!(
    treatment_plan_version_id: tpv2.id,
    client_id:                 alex_client.id,
    description:               "Practice the 5-4-3-2-1 grounding technique once per day — do it when you're calm so it's automatic when you need it. (5 things you see, 4 you feel, 3 you hear, 2 you smell, 1 you taste.)",
    completed:                 true,
    completed_at:              Time.zone.parse("2026-03-02 09:00:00")
  )

  HomeworkItem.create!(
    treatment_plan_version_id: tpv2.id,
    client_id:                 alex_client.id,
    description:               "Continue thought records — aim for one complete record for any high-intensity (7+) worry this week.",
    completed:                 true,
    completed_at:              Time.zone.parse("2026-03-01 21:00:00")
  )

  HomeworkItem.create!(
    treatment_plan_version_id: tpv2.id,
    client_id:                 alex_client.id,
    description:               "Keep up the behavioral activation: guitar and running. At least one of each this week.",
    completed:                 true,
    completed_at:              Time.zone.parse("2026-03-02 17:30:00")
  )

  # ── Session 5 — Mar 10 2026 — Social Anxiety & Progress Review ──────────────
  s5_transcript_pairs = [
    ["T", "Alex, it's good to see you. Two weeks since we last met — how have things been?"],
    ["C", "Better, I think. Like, measurably better. I haven't had another panic attack. I used the grounding technique twice and both times it stopped the anxiety from escalating."],
    ["T", "That's really significant. What were the situations?"],
    ["C", "Once before a code review where I was presenting my work to senior engineers — I felt the racing heart starting and I did the grounding thing quietly at my desk and it settled. The second time was actually at a social situation, a birthday dinner for a friend, and I was feeling really out of place and like everyone was more interesting than me. I did it in the bathroom and I was able to go back and enjoy the dinner."],
    ["T", "You used it in two completely different contexts and it worked in both. That's you building genuine coping capacity, not just managing a crisis. I want to note something: you went to a social event. That's also behavioral activation."],
    ["C", "Yeah, I nearly didn't go. I had an excuse ready."],
    ["T", "But you went. What made you go?"],
    ["C", "Honestly? I thought about what you said about avoidance making the fear stronger. And I thought — if I cancel this, I'm training my brain that social events are dangerous. I don't want to be someone who cancels on their friends."],
    ["T", "That's internalization of the CBT model. You're not just doing exercises, you're reasoning from principles. That's a major shift."],
    ["C", "It still felt bad for the first half hour. Then I got into a good conversation with someone I hadn't met before and the anxiety kind of faded."],
    ["T", "That's exactly how exposure works. The anxiety peaks and then it naturally comes down — if you stay in the situation. Every time you do that, the peak is a little lower next time. What about the core belief we identified — needing to have ambition and a plan?"],
    ["C", "I've been thinking about that a lot. I had another one-on-one with my manager and he asked a follow-up about my goals. This time I was more honest — I said I was focusing on deepening my craft right now rather than chasing a promotion. And he said that was exactly what the team needed."],
    ["T", "How did that feel?"],
    ["C", "Completely different from what I expected. I thought admitting I don't have a five-year plan would be a red flag. But he seemed to respect it."],
    ["T", "What does that do to the belief that you have to perform ambition to deserve your place?"],
    ["C", "It pokes a pretty big hole in it. I mean, it's one data point. But yeah."],
    ["T", "One data point repeated over time becomes a pattern. We'll keep collecting them. How's sleep?"],
    ["C", "Better. I'd say I sleep through most nights now. I still have an occasional early waking but it resolves faster."],
    ["T", "That's a big quality of life improvement. I want to introduce one more thing today: work on the residual social anxiety specifically in group settings, like the engineering all-hands or bigger team meetings. You seem more comfortable in one-on-ones but group contexts still spike the anxiety?"],
    ["C", "Yeah. I still sometimes feel invisible in big meetings, or I'll have something to say and then I'll wait too long and the moment passes. Or I'll say something and then replay it afterward."],
    ["T", "The post-event processing is still there for group settings. Let's work on that. For homework, I want you to set one small intention in each team meeting this week: contribute one comment or question, even a small one. Not to be impressive — just to make contact. And notice what actually happens when you speak."],
    ["C", "That sounds doable. I think I'm often more afraid of speaking up than I am in the moment when I actually do it."],
    ["T", "That anticipatory anxiety is almost always worse than the event. I also want to give you something longer-term to think about: is there a social situation you've been avoiding that you'd like to tackle in the next month? Something where you'd feel like you really got back to yourself."],
    ["C", "There's a casual Friday lunch my team does that I never go to. I always have a reason not to. I'd like to go to that."],
    ["T", "Let's make that a goal. Not homework this week — next session we'll talk about it as a planned exposure. You've made a lot of progress, Alex. Genuinely."],
    ["C", "Thank you. I feel it. It's strange — six months ago I would have said I'm just a stressed person and that's just how I am. And now it feels like there are things I can actually do."],
    ["T", "That shift in sense of agency is one of the most important things we can build. See you next week."]
  ]

  s5_content = s5_transcript_pairs.map { |(spk, txt)| "#{spk == 'T' ? 'Therapist' : 'Client'}: #{txt}" }.join("\n")

  sess5 = Session.create!(
    therapist_id:     therapist_profile.id,
    client_id:        alex_client.id,
    session_date:     Time.zone.parse("2026-03-10 10:00:00"),
    session_number:   5,
    duration_minutes: 50,
    status:           "completed",
    session_type:     "uploaded"
  )

  Transcript.create!(
    session_id:   sess5.id,
    content:      s5_content,
    source_type:  "uploaded",
    word_count:   s5_content.split.length,
    utterances:   build_utterances(s5_transcript_pairs),
    speaker_map:  SPEAKER_MAP
  )

  SessionSummary.create!(
    session_id:        sess5.id,
    therapist_summary: "Significant progress across all domains. No panic attacks since session 4. Grounding (5-4-3-2-1) used successfully twice — code review and social dinner. Client attended social event (birthday dinner) despite anticipatory anxiety; anxiety resolved once engaged. Core belief ('must demonstrate ambition') disrupted by manager feedback validating craft-focus over promotion ambition. Sleep substantially improved. Residual: group meeting anxiety, post-event processing in group settings, anticipatory anxiety. Next focus: group setting exposure (team lunch as planned exposure). Homework: one contribution per team meeting this week; note outcome.",
    client_summary:    "You're making real progress — no panic attacks, grounding is working, you went to the birthday dinner even when you wanted to cancel. You also had an honest conversation with your manager about your goals and it went better than you expected, which is great evidence against the 'I have to perform ambition' belief. This week: in each team meeting, make one contribution — a comment or a question, just to make contact. Notice what actually happens when you speak. We'll plan the team Friday lunch as an exposure next session.",
    key_themes:        ["progress review", "grounding success", "exposure working", "social event", "core belief challenge", "manager feedback", "group meeting anxiety", "anticipatory anxiety", "team lunch goal"]
  )

  tpv3 = TreatmentPlanVersion.create!(
    treatment_plan_id: tplan.id,
    version_number:    3,
    session_id:        sess5.id,
    source:            "ai_generated",
    change_summary:    "Progress review after session 5: grounding generalized, core belief challenged by real-world data; focus shifts to group settings and planned exposure (seed / demo).",
    therapist_content: {
      "presenting_concerns" => [
        "Marked gains: no panic since session 4; grounding used in work and social contexts",
        "Core belief about ambition/deserving role weakened after supportive manager conversation",
        "Residual group-meeting anxiety and post-event processing in larger forums"
      ],
      "goals" => [
        { "description" => "Maintain panic management skills and early use of grounding", "modality" => "CBT", "timeframe" => "ongoing" },
        { "description" => "Increase behavioral participation in group work settings", "modality" => "Exposure", "timeframe" => "4–6 weeks" },
        { "description" => "Complete planned exposure (team casual lunch)", "modality" => "Exposure", "timeframe" => "next 1–2 sessions" },
        { "description" => "Consolidate sleep gains", "modality" => "CBT-I (intro)", "timeframe" => "ongoing" }
      ],
      "interventions" => [
        { "name" => "Continued cognitive work", "modality" => "CBT", "description" => "Thought records for anticipatory anxiety in groups" },
        { "name" => "Group exposure hierarchy", "modality" => "CBT", "description" => "One intentional contribution per team meeting; log predictions vs. outcomes" },
        { "name" => "Planned social exposure", "modality" => "CBT", "description" => "Prepare team Friday lunch as graded exposure (next session)" },
        { "name" => "Relapse prevention", "modality" => "CBT", "description" => "Review early warning signs and skill menu (grounding, BA, thought records)" }
      ],
      "homework" => [
        "Each team meeting: one comment or question; afterward jot what you predicted vs. what actually happened",
        "Notice thoughts about the Friday team lunch without avoiding—bring notes next session"
      ],
      "strengths" => [
        "Internalizing CBT principles (choosing approach over avoidance)",
        "Behavioral activation and social attendance despite discomfort",
        "Strong alliance and consistent engagement"
      ],
      "barriers" => [
        "Anticipatory anxiety often exceeds in-the-moment difficulty—address with logged evidence"
      ],
      "diagnosis_considerations" => [
        "Generalized Anxiety Disorder; panic symptoms in remission with skills; social anxiety features in group contexts"
      ]
    },
    client_content: {
      "what_we_talked_about" =>
        "We celebrated solid progress: no new panic attacks, grounding worked before a code review and at a friend's birthday dinner, and you were honest with your manager about focusing on craft—which went better than you feared. Next we're targeting bigger meetings: small, planned contributions, and we'll shape the team lunch as a gentle exposure when you're ready.",
      "your_goals" => [
        "Keep using grounding when anxiety starts to climb",
        "Speak up once per team meeting and compare worries to what really happened",
        "Work toward joining the casual Friday lunch when we plan it together",
        "Protect the sleep gains you've made"
      ],
      "things_to_try" => [
        "One contribution per group meeting—aim for contact, not performance",
        "Write a quick before/after note: feared outcome vs. actual outcome",
        "Watch for 'anticipatory story' about the team lunch without acting on canceling yet"
      ],
      "your_strengths" => [
        "You're applying skills in different settings, not just in session",
        "You're testing old beliefs with new evidence",
        "You're showing up for people and activities that matter"
      ],
      "next_steps" => ["Bring meeting notes and any thoughts about the Friday lunch to the next session"]
    }
  )

  tplan.update!(current_version_id: tpv3.id)

  HomeworkItem.create!(
    treatment_plan_version_id: tpv3.id,
    client_id:                 alex_client.id,
    description:               "In each team meeting this week, make one contribution — a comment or question, even small. Not to impress, just to make contact. Write a brief note afterward about what actually happened (vs. what you feared).",
    completed:                 false
  )

  HomeworkItem.create!(
    treatment_plan_version_id: tpv3.id,
    client_id:                 alex_client.id,
    description:               "Think about attending the team Friday casual lunch — we'll discuss this as a planned exposure in the next session. No pressure to go yet, just start noticing your anticipatory thoughts about it.",
    completed:                 false
  )

end
# ─────────────────────────────────────────────────────────────────────────────

# Second therapist
therapist2 = User.find_or_create_by!(email: "therapist2@demo.health") do |u|
  u.name = "Dr. Michael Torres"
  u.role = "therapist"
  u.password = "demo123"
end

therapist_profile2 = Therapist.find_or_create_by!(user_id: therapist2.id) do |t|
  t.license_type = "LMFT"
  t.specialties = ["trauma", "family therapy", "EMDR"]
  t.preferences = {}
  t.slug = "dr-michael-torres"
end

# Five additional clients
["Jordan Kim", "Maya Patel", "Chris Wong", "Taylor Nguyen", "Sam Foster"].each_with_index do |name, i|
  email = "#{name.downcase.tr(" ", ".")}@demo.health"
  cu = User.find_or_create_by!(email: email) do |u|
    u.name = name
    u.role = "client"
    u.password = "demo123"
  end
  next if Client.exists?(user_id: cu.id)

  therapist_id = i.even? ? therapist_profile.id : therapist_profile2.id
  Client.create!(user_id: cu.id, therapist_id: therapist_id, name: name)
end

# ─── Dummy treatment plans for secondary demo clients ─────────────────────────
# Shapes match therapist PlanReview + client PlanView (JSONB). No sessions seeded.
# Idempotent: one TreatmentPlan per client.
dummy_plans = {
  "jordan.kim@demo.health" => {
    therapist: therapist_profile,
    therapist_content: {
      "presenting_concerns" => [
        "First-time therapy; anticipatory anxiety about starting care",
        "Stress related to new routines and 'getting it right' in work and relationships",
        "Occasional sleep difficulty when anticipating next-day responsibilities"
      ],
      "goals" => [
        { "description" => "Build comfort with the therapy process and a sustainable routine", "modality" => "Supportive / CBT-informed", "timeframe" => "4–6 weeks" },
        { "description" => "Identify early worry patterns and one go-to coping step", "modality" => "CBT", "timeframe" => "6–8 weeks" },
        { "description" => "Improve wind-down and sleep on high-demand nights", "modality" => "Sleep skills", "timeframe" => "ongoing" }
      ],
      "interventions" => [
        { "name" => "Rapport and orientation", "modality" => "Supportive", "description" => "Clarify expectations, pace, and confidentiality" },
        { "name" => "Psychoeducation", "modality" => "CBT-informed", "description" => "Anxiety as alarm system; gentle self-monitoring" },
        { "name" => "Coping menu", "modality" => "CBT", "description" => "Breathing, grounding, and brief behavioral experiments" }
      ],
      "homework" => [
        "Note one moment daily when anxiety showed up and what you did that helped even a little",
        "Try a 5-minute wind-down routine before bed on two nights this week"
      ],
      "strengths" => [
        "Motivated to engage despite nervousness",
        "Clear communicator",
        "Willing to ask questions about the process"
      ],
      "diagnosis_considerations" => [
        "Adjustment with anxiety features (provisional); formal dx TBD after further assessment"
      ]
    },
    client_content: {
      "what_we_talked_about" =>
        "We focused on what it feels like to start therapy and how anxiety can spike when you're trying new things. We picked small, realistic steps to notice worry and practice one calming habit.",
      "your_goals" => [
        "Feel less alone with worry as you get used to therapy",
        "Catch one worry pattern early and respond with a skill you choose",
        "Sleep a bit easier on busy nights"
      ],
      "things_to_try" => [
        "One daily anxiety check-in (what showed up, what helped)",
        "A short wind-down before bed twice this week"
      ],
      "your_strengths" => [
        "You showed up—that matters",
        "You're curious about how therapy works",
        "You're honest about what feels hard"
      ],
      "next_steps" => ["Bring your notes to the next session"]
    },
    homework: [
      "Daily: one line about anxiety + what helped (even 5%).",
      "Two nights: 5-minute wind-down before bed."
    ]
  },
  "maya.patel@demo.health" => {
    therapist: therapist_profile2,
    therapist_content: {
      "presenting_concerns" => [
        "Low mood, fatigue, and loss of interest persisting several weeks",
        "Tension with partner about division of household labor",
        "Guilt about 'not keeping up' at work and home"
      ],
      "goals" => [
        { "description" => "Stabilize daily routine (sleep, meals, movement)", "modality" => "Behavioral activation", "timeframe" => "4 weeks" },
        { "description" => "Improve communication with partner using structured dialogue", "modality" => "EFT-informed / communication skills", "timeframe" => "6–10 weeks" },
        { "description" => "Reduce self-critical thoughts with thought balancing", "modality" => "CBT", "timeframe" => "8 weeks" }
      ],
      "interventions" => [
        { "name" => "Behavioral activation", "modality" => "BA", "description" => "Small scheduled pleasant and mastery activities" },
        { "name" => "Couples communication coaching", "modality" => "LMFT", "description" => "Speaker-listener technique; de-escalation cues" },
        { "name" => "Cognitive restructuring", "modality" => "CBT", "description" => "Identify guilt cognitions and generate balanced alternatives" }
      ],
      "homework" => [
        "Schedule two 20-minute activities that usually give even mild enjoyment",
        "One structured conversation with partner using speaker-listener format",
        "Log three self-critical thoughts and one balanced line for each"
      ],
      "strengths" => [
        "Strong commitment to relationships",
        "Insight into guilt and fairness themes",
        "Follows through when tasks are concrete"
      ],
      "barriers" => [
        "Low energy can shrink homework—keep steps very small"
      ],
      "diagnosis_considerations" => [
        "Major Depressive Disorder, mild-moderate (provisional); relational stressors"
      ]
    },
    client_content: {
      "what_we_talked_about" =>
        "We looked at how low mood and fatigue connect to feeling overloaded at home and at work. We planned tiny activities to rebuild momentum and a clearer way to talk with your partner so fights slow down.",
      "your_goals" => [
        "Feel a bit more energy in the week",
        "Have one calmer conversation with your partner about chores",
        "Be a little kinder to yourself when guilt shows up"
      ],
      "things_to_try" => [
        "Two short activities you used to like—even if motivation is low",
        "Speaker-listener practice once",
        "Three guilt thoughts rewritten in a fairer voice"
      ],
      "your_strengths" => [
        "You care deeply about doing right by people",
        "You notice patterns in how you talk to yourself",
        "You're willing to try structured tools"
      ],
      "next_steps" => ["Share how the activities and conversation felt next session"]
    },
    homework: [
      "Two 20-minute pleasant/mastery activities.",
      "One speaker-listener talk with partner.",
      "Three guilt thoughts + balanced responses."
    ]
  },
  "chris.wong@demo.health" => {
    therapist: therapist_profile,
    therapist_content: {
      "presenting_concerns" => [
        "Chronic work overload; difficulty disconnecting after hours",
        "Irritability with coworkers; fear of disappointing the team",
        "Headaches and muscle tension during high-deadline weeks"
      ],
      "goals" => [
        { "description" => "Set clearer work boundaries without catastrophic fears", "modality" => "CBT", "timeframe" => "6 weeks" },
        { "description" => "Reduce somatic stress cues via pacing and recovery", "modality" => "Behavioral / mindfulness intro", "timeframe" => "4–8 weeks" },
        { "description" => "Repair working relationships with assertive communication", "modality" => "CBT / assertiveness", "timeframe" => "ongoing" }
      ],
      "interventions" => [
        { "name" => "Values-clarification", "modality" => "ACT-informed", "description" => "Link boundaries to what matters long-term" },
        { "name" => "Worry scheduling", "modality" => "CBT", "description" => "Contain rumination to a short daily window" },
        { "name" => "Pacing and recovery", "modality" => "Behavioral", "description" => "Micro-breaks, sleep protection, basic movement" }
      ],
      "homework" => [
        "Pick one boundary experiment (e.g., no email after 8pm) for three weeknights",
        "10-minute walk or stretch block on four days",
        "One assertive message to a teammate using DESC script (draft in session)"
      ],
      "strengths" => [
        "High conscientiousness and team loyalty",
        "Recognizes early that burnout pattern is unsustainable",
        "Responds well to structured behavioral plans"
      ],
      "diagnosis_considerations" => [
        "Occupational burnout / adjustment with anxiety features (provisional)"
      ]
    },
    client_content: {
      "what_we_talked_about" =>
        "We mapped how always being 'on' at work feeds irritability and tension in your body. We chose one small boundary to test and a few recovery habits that don't depend on motivation.",
      "your_goals" => [
        "Turn off work brain a little earlier some nights",
        "Move your body briefly most days",
        "Say one clear request at work without over-apologizing"
      ],
      "things_to_try" => [
        "Three nights: boundary experiment you picked",
        "Four days: 10-minute walk or stretch",
        "Draft one DESC message before sending"
      ],
      "your_strengths" => [
        "You care about your team",
        "You can spot the burnout pattern",
        "You're willing to test small changes"
      ],
      "next_steps" => ["Note what felt scary vs. what actually happened with the boundary"]
    },
    homework: [
      "Three nights: chosen work boundary.",
      "Four days: 10-minute movement.",
      "One DESC-style work message."
    ]
  },
  "taylor.nguyen@demo.health" => {
    therapist: therapist_profile2,
    therapist_content: {
      "presenting_concerns" => [
        "Frequent conflict with a parent about career choices and independence",
        "Feeling 'stuck in the middle' between family expectations and personal goals",
        "Guilt when setting limits on calls and visits"
      ],
      "goals" => [
        { "description" => "Clarify personal boundaries while preserving family connection", "modality" => "Family systems / communication", "timeframe" => "8–12 weeks" },
        { "description" => "Reduce guilt-driven over-accommodation", "modality" => "CBT-informed", "timeframe" => "6–10 weeks" },
        { "description" => "Increase support outside immediate family", "modality" => "Supportive", "timeframe" => "ongoing" }
      ],
      "interventions" => [
        { "name" => "Genogram / roles map", "modality" => "Family systems", "description" => "Visualize expectations and alliances" },
        { "name" => "Boundary scripts", "modality" => "Communication", "description" => "Short, respectful limit-setting lines" },
        { "name" => "Guilt cognitions", "modality" => "CBT", "description" => "Test beliefs about responsibility and loyalty" }
      ],
      "homework" => [
        "Write three boundaries you want (small, medium, large) and pick the smallest to practice",
        "One conversation using a boundary script; note family response",
        "Reach out to one non-family support (friend, peer group, hobby)"
      ],
      "strengths" => [
        "Loyal and thoughtful about family impact",
        "Clear values about autonomy",
        "Humor and resilience under stress"
      ],
      "diagnosis_considerations" => [
        "Relational distress; rule out anxiety/depression if mood symptoms worsen"
      ]
    },
    client_content: {
      "what_we_talked_about" =>
        "We explored the push-pull between what your family expects and the life you want. We sorted boundaries into small steps and practiced wording that is firm but still caring.",
      "your_goals" => [
        "Say one small no (or not-now) without drowning in guilt",
        "Stay connected to family without losing your own direction",
        "Build support outside the family circle"
      ],
      "things_to_try" => [
        "Pick the smallest boundary from your list",
        "Use your script once and notice what happened",
        "One check-in with a friend or community"
      ],
      "your_strengths" => [
        "You love your family and still honor your own path",
        "You're brave enough to talk about guilt out loud",
        "You can laugh even when it's heavy"
      ],
      "next_steps" => ["Bring what worked and what felt messy from the boundary try"]
    },
    homework: [
      "Practice smallest boundary once.",
      "One support contact outside family."
    ]
  },
  "sam.foster@demo.health" => {
    therapist: therapist_profile,
    therapist_content: {
      "presenting_concerns" => [
        "Hypervigilance in crowds and on transit; startle response",
        "Avoidance of certain neighborhoods after an upsetting incident",
        "Shame about 'overreacting' when reminded of the past"
      ],
      "goals" => [
        { "description" => "Stabilize nervous system responses with grounding and pacing", "modality" => "Trauma-informed CBT", "timeframe" => "6–10 weeks" },
        { "description" => "Gradually widen safe activities using a fear hierarchy", "modality" => "Exposure (collaborative)", "timeframe" => "8–12 weeks" },
        { "description" => "Reduce shame narrative; build self-compassion", "modality" => "CFT-informed", "timeframe" => "ongoing" }
      ],
      "interventions" => [
        { "name" => "Safety and stabilization", "modality" => "Trauma-informed", "description" => "Grounding, window of tolerance, no forced retelling" },
        { "name" => "Graded exposure", "modality" => "CBT", "description" => "Hierarchy built together; client controls pace" },
        { "name" => "Cognitive processing", "modality" => "CBT", "description" => "Update stuck beliefs about blame and weakness" }
      ],
      "homework" => [
        "Daily: 3 minutes of grounding when anxiety is under a 5/10",
        "One step on the hierarchy (pre-agreed) with post-exposure notes",
        "Write one compassionate line you'd say to a friend, then read it to yourself"
      ],
      "strengths" => [
        "Strong survival skills and awareness of triggers",
        "Trust-building in therapeutic relationship",
        "Commitment to moving at a safe pace"
      ],
      "barriers" => [
        "Shame may spike after exposure—normalize and plan for debrief"
      ],
      "diagnosis_considerations" => [
        "PTSD symptoms (provisional); formal assessment ongoing"
      ]
    },
    client_content: {
      "what_we_talked_about" =>
        "We focused on helping your body feel safer day to day without pushing you to relive hard memories. You chose a tiny step toward places you've been avoiding, at a speed that respects your limits.",
      "your_goals" => [
        "Feel less on-edge in ordinary public situations",
        "Take one small step toward a place you've been avoiding",
        "Replace shame thoughts with something fairer"
      ],
      "things_to_try" => [
        "Short daily grounding when anxiety is mild",
        "One hierarchy step we agreed on",
        "One self-compassion line borrowed from how you'd support a friend"
      ],
      "your_strengths" => [
        "You know your limits—that's wisdom",
        "You keep showing up even when it's scary",
        "You're building trust step by step"
      ],
      "next_steps" => ["Share how the hierarchy step felt (body + thoughts) next time"]
    },
    homework: [
      "Daily grounding when calm enough.",
      "One agreed hierarchy step + notes.",
      "One compassion line for yourself."
    ]
  }
}.freeze

dummy_plans.each do |email, spec|
  user = User.find_by(email: email)
  next unless user

  client = Client.find_by(user_id: user.id)
  next unless client
  next if TreatmentPlan.exists?(client_id: client.id)

  tp = TreatmentPlan.create!(
    client_id:    client.id,
    therapist_id: spec[:therapist].id,
    status:       "draft"
  )

  tpv = TreatmentPlanVersion.create!(
    treatment_plan_id: tp.id,
    version_number:    1,
    session_id:        nil,
    source:            "ai_generated",
    change_summary:    "Demo treatment plan (seed data; not generated from a transcript).",
    therapist_content: spec[:therapist_content],
    client_content:    spec[:client_content]
  )

  tp.update!(current_version_id: tpv.id)

  spec[:homework].each do |desc|
    HomeworkItem.create!(
      treatment_plan_version_id: tpv.id,
      client_id:                 client.id,
      description:               desc,
      completed:                 false
    )
  end
end

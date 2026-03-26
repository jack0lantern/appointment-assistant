# frozen_string_literal: true

# Curated emotional-support copy with citations to public health / clinical education pages.
# The agent must pass citations through to end users (see ContextBuilder + tool descriptions).
class EmotionalSupportService
  GROUNDING_EXERCISES = [
    {
      exercise:
        "Let's try a quick grounding exercise. Look around and name:\n" \
        "- **5** things you can see\n" \
        "- **4** things you can touch\n" \
        "- **3** things you can hear\n" \
        "- **2** things you can smell\n" \
        "- **1** thing you can taste\n\n" \
        "Take your time with each one.",
      citation:
        "NHS inform (Scotland), “Grounding exercises” — " \
        "https://www.nhsinform.scot/healthy-living/mental-wellbeing/" \
        "breathing-and-relaxation-exercises/grounding-exercises/"
    },
    {
      exercise:
        "Here's a simple breathing exercise:\n" \
        "1. Breathe in slowly for **4 counts**\n" \
        "2. Hold for **4 counts**\n" \
        "3. Breathe out slowly for **6 counts**\n" \
        "4. Repeat 3-4 times\n\n" \
        "This helps activate your body's natural calm response.",
      citation:
        "National Center for Complementary and Integrative Health (NIH), " \
        "“Relaxation Techniques: What You Need To Know” — " \
        "https://www.nccih.nih.gov/health/relaxation-techniques-what-you-need-to-know"
    },
    {
      exercise:
        "Try placing both feet flat on the floor. Press them down gently and " \
        "notice the sensation of being grounded. Take three slow breaths, " \
        "focusing on the feeling of your feet connecting with the ground.",
      citation:
        "National Institute of Mental Health (NIH), “Caring for Your Mental Health” " \
        "(relaxation and body awareness) — " \
        "https://www.nimh.nih.gov/health/topics/caring-for-your-mental-health"
    }
  ].freeze

  VALIDATION_MESSAGES = [
    "What you're feeling is completely valid. It takes courage to reach out, and you've already taken that step.",
    "It's okay to feel this way. Many people experience similar feelings, and you don't have to face them alone.",
    "Thank you for sharing that with me. Your feelings matter, and it's important to acknowledge them.",
    "Starting therapy can bring up a lot of emotions — that's completely normal and actually a sign of strength."
  ].freeze

  PSYCHOEDUCATION = {
    "anxiety" => [
      "Anxiety is your brain's way of trying to protect you. While it can feel overwhelming, " \
      "it's a natural response that can be managed with the right tools and support.",
      "Many people find that anxiety decreases once they begin working with a therapist. " \
      "You don't have to have it all figured out before your first session."
    ],
    "first_session" => [
      "Your first session is mostly about getting to know your therapist. There's no wrong " \
      "way to start — you can share as much or as little as you're comfortable with.",
      "It's normal to feel nervous before a first session. Your therapist is trained to " \
      "help you feel at ease, and everything you share is confidential."
    ],
    "therapy_general" => [
      "Therapy is a collaborative process. You and your therapist work together to " \
      "understand your experiences and develop strategies that work for you.",
      "Progress in therapy isn't always linear — some weeks feel easier than others. " \
      "That's completely normal and part of the process."
    ]
  }.freeze

  PSYCHOEDUCATION_CITATIONS = {
    "anxiety" =>
      "National Institute of Mental Health (NIH), “Anxiety Disorders” — " \
      "https://www.nimh.nih.gov/health/topics/anxiety-disorders",
    "first_session" =>
      "National Institute of Mental Health (NIH), “Psychotherapies” — " \
      "https://www.nimh.nih.gov/health/topics/psychotherapies",
    "therapy_general" =>
      "American Psychological Association, “Psychotherapy” — " \
      "https://www.apa.org/topics/psychotherapy"
  }.freeze

  WHAT_TO_EXPECT = {
    "onboarding" =>
      "Here's what to expect during onboarding:\n" \
      "1. **Basic information** — We'll collect some general details to match you with the right therapist\n" \
      "2. **Insurance verification** — If applicable, we'll help verify your coverage\n" \
      "3. **Scheduling** — We'll find a time that works for you\n\n" \
      "The whole process typically takes about 10-15 minutes.",
    "first_appointment" =>
      "Here's what to expect for your first appointment:\n" \
      "- It usually lasts about **50 minutes**\n" \
      "- Your therapist will ask about what brings you to therapy\n" \
      "- You can share at your own pace — there's no pressure\n" \
      "- Together, you'll start to outline goals for your work\n\n" \
      "Remember: there are no wrong answers."
  }.freeze

  WHAT_TO_EXPECT_CITATIONS = {
    "onboarding" =>
      "National Institute of Mental Health (NIH), “Help for Mental Illnesses” — " \
      "https://www.nimh.nih.gov/health/find-help",
    "first_appointment" =>
      "National Institute of Mental Health (NIH), “Psychotherapies” — " \
      "https://www.nimh.nih.gov/health/topics/psychotherapies"
  }.freeze

  def self.grounding_exercise
    GROUNDING_EXERCISES.sample
  end

  def self.validation_message
    VALIDATION_MESSAGES.sample
  end

  def self.psychoeducation(topic)
    snippets = PSYCHOEDUCATION[topic]
    return unless snippets

    {
      content: snippets.sample,
      citation: PSYCHOEDUCATION_CITATIONS[topic]
    }
  end

  def self.what_to_expect(context)
    text = WHAT_TO_EXPECT[context]
    return unless text

    {
      content: text,
      citation: WHAT_TO_EXPECT_CITATIONS[context]
    }
  end
end

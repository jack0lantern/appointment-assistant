# frozen_string_literal: true

require "rails_helper"

RSpec.describe SafetyScanner do
  subject(:scanner) { described_class.new }

  def flag_types(flags)
    flags.map(&:flag_type)
  end

  def safety_risk_flags(flags)
    flags.select { |f| f.category == SafetyScanner::CATEGORY_SAFETY_RISK }
  end

  def clinical_observation_flags(flags)
    flags.select { |f| f.category == SafetyScanner::CATEGORY_CLINICAL_OBSERVATION }
  end

  def clinician_omission_flags(flags)
    flags.select { |f| f.category == SafetyScanner::CATEGORY_CLINICIAN_OMISSION }
  end

  # ---------------------------------------------------------------------------
  # Core safety risk detection (should still flag)
  # ---------------------------------------------------------------------------

  describe "core safety risk detection" do
    it "detects suicidal ideation" do
      lines = [
        "Therapist: How are you feeling?",
        "Client: I want to kill myself sometimes."
      ]
      flags = scanner.scan_transcript(lines, [])
      expect(flag_types(safety_risk_flags(flags))).to include("suicidal_ideation")
    end

    it "detects self-harm" do
      lines = [
        "Therapist: Can you tell me more?",
        "Client: I've been cutting myself on my arms."
      ]
      flags = scanner.scan_transcript(lines, [])
      expect(flag_types(safety_risk_flags(flags))).to include("self_harm")
    end

    it "detects harm to others" do
      lines = [
        "Therapist: What happened?",
        "Client: I want to hurt him so badly."
      ]
      flags = scanner.scan_transcript(lines, [])
      expect(flag_types(safety_risk_flags(flags))).to include("harm_to_others")
    end

    it "detects substance crisis" do
      lines = [
        "Therapist: Tell me about your drinking.",
        "Client: I blacked out from drinking last weekend."
      ]
      flags = scanner.scan_transcript(lines, [])
      expect(flag_types(safety_risk_flags(flags))).to include("substance_crisis")
    end

    it "does not flag anger" do
      lines = [
        "Therapist: What happened with your husband?",
        "Client: I'm really angry at my husband.",
        "Therapist: Tell me more about that frustration."
      ]
      flags = safety_risk_flags(scanner.scan_transcript(lines, []))
      expect(flags).to be_empty, "False positive - anger should not flag: #{flags}"
    end

    it "flags SI even with treatment context in sentence" do
      lines = [
        "Client: I wanted to kill myself before this meeting."
      ]
      flags = safety_risk_flags(scanner.scan_transcript(lines, []))
      expect(flag_types(flags)).to include("suicidal_ideation")
    end

    it "flags historical self-harm" do
      lines = [
        "Client: I used to self-harm but stopped years ago."
      ]
      flags = scanner.scan_transcript(lines, [])
      expect(flags).not_to be_empty
    end

    it "deduplicates against existing AI flags" do
      lines = [
        "Client: I sometimes think about suicide."
      ]
      existing_ai_flag = SafetyScanner::SafetyFlagData.new(
        flag_type: "suicidal_ideation",
        severity: "high",
        description: "Suicidal ideation mentioned",
        transcript_excerpt: "I sometimes think about suicide",
        line_start: 1,
        line_end: 1,
        source: "ai",
        category: SafetyScanner::CATEGORY_SAFETY_RISK
      )
      flags = scanner.scan_transcript(lines, [existing_ai_flag])
      regex_si_flags = flags.select { |f| f.source == "regex" && f.flag_type == "suicidal_ideation" }
      expect(regex_si_flags).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Contextual disambiguation for hopelessness language
  # ---------------------------------------------------------------------------

  describe "contextual disambiguation" do
    it "does not flag treatment-directed hopelessness" do
      lines = [
        "Client: What's the point. I don't know if this is helping."
      ]
      flags = safety_risk_flags(scanner.scan_transcript(lines, []))
      distress_flags = flags.select { |f| f.flag_type == "severe_distress" }
      expect(distress_flags).to be_empty,
        "Treatment-directed hopelessness should not flag: #{distress_flags}"
    end

    it "flags existential hopelessness with incidental treatment mention" do
      lines = [
        "Client: I feel hopeless, coming here doesn't change that nothing matters."
      ]
      flags = safety_risk_flags(scanner.scan_transcript(lines, []))
      distress_flags = flags.select { |f| f.flag_type == "severe_distress" }
      expect(distress_flags).not_to be_empty,
        "Existential hopelessness with incidental treatment mention should still flag"
    end

    it "flags existential hopelessness without treatment context" do
      lines = [
        "Client: Nothing will ever get better. I feel hopeless."
      ]
      flags = safety_risk_flags(scanner.scan_transcript(lines, []))
      distress_flags = flags.select { |f| f.flag_type == "severe_distress" }
      expect(distress_flags).not_to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Separate symptom flags from safety flags
  # ---------------------------------------------------------------------------

  describe "symptom vs safety separation" do
    it "classifies depression symptoms as clinical observations" do
      lines = [
        "Client: I sleep ten hours and still feel exhausted.",
        "Client: I stopped seeing my friends.",
        "Client: I don't enjoy anything anymore.",
        "Client: I've been skipping meals."
      ]
      flags = scanner.scan_transcript(lines, [])
      safety = safety_risk_flags(flags)
      observations = clinical_observation_flags(flags)

      expect(safety).to be_empty, "Symptoms should not be safety flags: #{safety}"
      expect(observations).not_to be_empty
    end

    it "does not count symptoms as safety risk" do
      lines = [
        "Therapist: How have you been sleeping?",
        "Client: I sleep too much. Like eleven hours.",
        "Therapist: And your social life?",
        "Client: I stopped going out. I'm isolating.",
        "Therapist: Have you thought about hurting yourself?",
        "Client: No, nothing like that."
      ]
      flags = scanner.scan_transcript(lines, [])
      safety_count = safety_risk_flags(flags).length
      expect(safety_count).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # Multi-signal convergence for medium-severity flags
  # ---------------------------------------------------------------------------

  describe "multi-signal convergence" do
    it "does not flag single medium distress signal" do
      lines = [
        "Client: I had a panic attack last night."
      ]
      flags = safety_risk_flags(scanner.scan_transcript(lines, []))
      medium_flags = flags.select { |f| f.severity == "medium" }
      expect(medium_flags).to be_empty,
        "Single medium signal should not flag: #{medium_flags}"
    end

    it "flags multiple medium distress signals" do
      lines = [
        "Client: I had a panic attack and I feel like I'm dissociating.",
        "Client: I also can't breathe sometimes and don't feel real."
      ]
      flags = safety_risk_flags(scanner.scan_transcript(lines, []))
      medium_flags = flags.select { |f| f.severity == "medium" }
      expect(medium_flags.length).to be >= 2
    end
  end

  # ---------------------------------------------------------------------------
  # SI probe absence detector
  # ---------------------------------------------------------------------------

  describe "SI probe absence detection" do
    it "detects absence of SI probe with multi-symptom depression" do
      lines = [
        "Therapist: How have you been?",
        "Client: I sleep too much, maybe eleven hours a day.",
        "Client: I stopped seeing friends. I'm withdrawing from everyone.",
        "Client: I don't enjoy anything anymore. Not even basketball.",
        "Client: I've been skipping meals.",
        "Client: I can't focus at work at all.",
        "Therapist: Let's work on behavioral activation."
      ]
      flags = scanner.scan_transcript(lines, [])
      omission = clinician_omission_flags(flags)
      expect(omission.length).to eq(1)
      expect(omission[0].flag_type).to eq("si_screen_absent")
    end

    it "does not flag when therapist conducts SI screen" do
      lines = [
        "Therapist: How have you been?",
        "Client: I sleep too much, maybe eleven hours a day.",
        "Client: I stopped seeing friends. I'm withdrawing from everyone.",
        "Client: I don't enjoy anything anymore.",
        "Client: I've been skipping meals.",
        "Client: I can't focus at work.",
        "Therapist: Have you had any thoughts about hurting yourself?",
        "Client: No, nothing like that."
      ]
      flags = scanner.scan_transcript(lines, [])
      omission = clinician_omission_flags(flags)
      expect(omission).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Substance crisis: behavioral indicator detection
  # ---------------------------------------------------------------------------

  describe "substance crisis behavioral indicators" do
    it "flags blackout without 'from drinking' qualifier" do
      lines = [
        "Client: I blacked out for about four hours last weekend."
      ]
      flags = safety_risk_flags(scanner.scan_transcript(lines, []))
      expect(flag_types(flags)).to include("substance_crisis")
    end

    it "flags escalating frequency" do
      lines = [
        "Client: It used to be just weekends but now I'm drinking four or five times a week."
      ]
      flags = safety_risk_flags(scanner.scan_transcript(lines, []))
      expect(flag_types(flags)).to include("substance_crisis")
    end

    it "flags high quantity drinking" do
      lines = [
        "Client: When I go out I have like six or seven drinks plus a few shots."
      ]
      flags = safety_risk_flags(scanner.scan_transcript(lines, []))
      expect(flag_types(flags)).to include("substance_crisis")
    end

    it "flags resumed use after harmful event" do
      lines = [
        "Client: Two days after the blackout I started drinking again."
      ]
      flags = safety_risk_flags(scanner.scan_transcript(lines, []))
      expect(flag_types(flags)).to include("substance_crisis")
    end

    it "flags found unconscious" do
      lines = [
        "Client: They found me passed out in my car."
      ]
      flags = safety_risk_flags(scanner.scan_transcript(lines, []))
      expect(flag_types(flags)).to include("substance_crisis")
    end
  end

  # ---------------------------------------------------------------------------
  # Blackout as standalone high-severity trigger
  # ---------------------------------------------------------------------------

  describe "blackout severity" do
    it "reports blackout as high severity" do
      lines = [
        "Client: I blacked out for about four hours."
      ]
      flags = safety_risk_flags(scanner.scan_transcript(lines, []))
      substance_flags = flags.select { |f| f.flag_type == "substance_crisis" }
      expect(substance_flags.length).to be >= 1
      expect(substance_flags.any? { |f| %w[high critical].include?(f.severity) }).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-domain co-occurrence
  # ---------------------------------------------------------------------------

  describe "substance multi-domain signals" do
    it "detects signals from different substance risk dimensions" do
      lines = [
        "Therapist: Tell me about your drinking.",
        "Client: I've been drinking more and more. Four or five times a week now.",
        "Client: Last weekend I blacked out for about four hours.",
        "Client: It's the only thing that helps me not think about losing her."
      ]
      flags = safety_risk_flags(scanner.scan_transcript(lines, []))
      substance_flags = flags.select { |f| f.flag_type == "substance_crisis" }
      expect(substance_flags.length).to be >= 2
    end
  end

  # ---------------------------------------------------------------------------
  # Substance safety screen absence
  # ---------------------------------------------------------------------------

  describe "substance screen absence" do
    it "flags absence when escalation and blackout present" do
      lines = [
        "Therapist: How has your week been?",
        "Client: I've been drinking more, like four or five times a week.",
        "Client: Last weekend I blacked out for about four hours.",
        "Client: They found me passed out in my car.",
        "Client: I started drinking again two days later.",
        "Therapist: Let's talk about some coping strategies."
      ]
      flags = scanner.scan_transcript(lines, [])
      omission = clinician_omission_flags(flags)
      substance_omissions = omission.select { |f| f.flag_type == "substance_screen_absent" }
      expect(substance_omissions.length).to eq(1)
    end

    it "does not flag when therapist conducts substance screen" do
      lines = [
        "Therapist: How has your week been?",
        "Client: I've been drinking more, like four or five times a week.",
        "Client: Last weekend I blacked out for about four hours.",
        "Therapist: Have you ever felt you needed to cut down on your drinking?",
        "Client: Maybe, I don't know."
      ]
      flags = scanner.scan_transcript(lines, [])
      omission = clinician_omission_flags(flags)
      substance_omissions = omission.select { |f| f.flag_type == "substance_screen_absent" }
      expect(substance_omissions).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Minimizing language should not suppress behavioral evidence
  # ---------------------------------------------------------------------------

  describe "minimizing language" do
    it "does not suppress flags when client minimizes" do
      lines = [
        "Client: I'm fine, it's pretty normal for me.",
        "Client: I usually have about six or seven beers when I go out.",
        "Client: I blacked out last weekend but I'm fine now."
      ]
      flags = safety_risk_flags(scanner.scan_transcript(lines, []))
      substance_flags = flags.select { |f| f.flag_type == "substance_crisis" }
      expect(substance_flags.length).to be >= 1
    end
  end

  # ---------------------------------------------------------------------------
  # Integration: standard depression session
  # ---------------------------------------------------------------------------

  describe "integration: standard depression session" do
    it "produces zero safety_risk flags for standard depression assessment" do
      lines = [
        "Therapist: How has your week been?",
        "Client: I almost didn't come. What's the point. I don't know if this is helping.",
        "Therapist: That feeling of what's the point — has that been showing up a lot lately?",
        "Client: I sleep ten, eleven hours and still feel exhausted.",
        "Client: I stopped playing basketball with my friends. Haven't gone in over a month.",
        "Client: My buddy texts me every Friday. Last week I didn't even respond.",
        "Client: Being around people takes so much energy. I feel like I'm bringing everyone down.",
        "Client: I used to like cooking. I haven't done that in weeks.",
        "Client: I stare at my screen for hours and barely get anything done.",
        "Therapist: Let's try behavioral activation this week."
      ]
      flags = scanner.scan_transcript(lines, [])
      safety = safety_risk_flags(flags)
      expect(safety).to be_empty,
        "Standard depression session should not produce safety_risk flags: #{safety}"
    end
  end
end

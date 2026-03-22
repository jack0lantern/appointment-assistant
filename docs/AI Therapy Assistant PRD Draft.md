# **Product Requirements Document (PRD): AI-Powered Therapy Onboarding Assistant**

## **1\. Project Overview & Objectives**

**Problem Statement:** Users seeking mental health services face high cognitive and emotional friction during onboarding. Complex data entry (intake forms, insurance uploads) and the stress of finding the right provider lead to high drop-off rates.

**Solution:** A conversational, AI-driven onboarding assistant that handles triage, document processing, provider matching, and scheduling.

**The "Credal" Imperative:** Because this system handles highly sensitive Personally Identifiable Information (PII) and Protected Health Information (PHI), it must be built with strict AI governance, automated PII redaction, and scoped agent actions to prevent data leakage or unsafe AI behavior.

## **2\. Tech Stack & Architecture**

* **AI Orchestration:** TypeScript / LangGraph (Manages cyclical agent workflows, state, and tool execution).  
* **Frontend:** React/JS (Chat interface rendering structured outputs and rich UI cards).

## **3\. LangGraph Architecture & State Management**

The system operates as a state machine using LangGraph. The graph routes the user dynamically based on their database status and conversational intent.

## **3.1. Graph State Definition (TypeScript)**

The state object passed between nodes tracks the user's progress and securely holds extracted entities.

TypeScript

import { BaseMessage } from "@langchain/core/messages";

export interface OnboardingState {  
  messages: BaseMessage\[\];                 // Full chat history  
  isNewUser: boolean;                      // Determines if intake flow is needed  
  hasCompletedIntake: boolean;             // True if history/docs are saved  
  assignedTherapistId: string | null;      // Pre-assigned via Deep Link/DB  
  providerSearchResults: Array\<any\> | null;// Stored JSON from Search Tool  
  selectedTherapistId: string | null;      // Extracted upon user confirmation  
  riskLevel: "low" | "medium" | "crisis";  // Maintained by Risk Evaluator  
  docsVerified: boolean;                   // Maintained by Doc Processor  
  appointmentId: string | null;            // Maintained by Scheduler  
}

## **3.2. Core Nodes (Agents & Tools)**

1. **Intake\_Agent:** The primary LLM conversationalist. Gathers clinical needs, demographic info, and provides empathetic responses.  
2. **Risk\_Evaluator (Guardrail):** A background sentiment/classifier node that runs on every input to detect crisis keywords (self-harm, severe distress).  
3. **Therapist\_Search (Tool):** Extracts search parameters (specialty, name, gender) and queries to return structured provider matches.  
4. **Document\_Processor (Tool):** Handles image-to-text for IDs/Insurance, heavily reliant on PII masking before data is stored.  
5. **Scheduling\_Tool (Tool):** Uses scoped actions to securely query the selected therapist's availability and post a booking.  
6. **Human\_Escalation:** Triggers standard fallback protocols, pausing AI interaction and alerting human staff via the backend.

## **3.3. System Logic Flow (Mermaid)**

Code snippet

graph TD  
    Start((Start)) \--\> CheckStatus{Check User DB Status}  
      
    %% Routing logic based on existing data  
    CheckStatus \-- "New User" \--\> IntakeFlow\[Intake & Documents\]  
    IntakeFlow \--\> TherapistSearch\[Therapist Search Tool\]  
      
    CheckStatus \-- "Returning: Needs Therapist" \--\> TherapistSearch  
    CheckStatus \-- "Returning: Has Therapist" \--\> RiskCheck{Risk Evaluator}  
      
    TherapistSearch \-- "Therapist Selected" \--\> RiskCheck  
      
    %% Universal Guardrail  
    RiskCheck \-- "Safe" \--\> Scheduler\[Scheduling Tool\]  
    Scheduler \--\> End((End))  
      
    RiskCheck \-- "Crisis Detected" \--\> HumanAlert\[Human Escalation\]  
    HumanAlert \--\> End

## **4\. Key Implementation Details & Features**

## **4.1. Provider Matching (Zero-ID UX)**

Users will *never* interact with raw database IDs. Therapist matching is handled invisibly via two primary methods:

* **Deep Linking (Pre-Assigned):** Users arriving via a referral link (e.g., /onboard/dr-smith) have the assignedTherapistId injected into the Graph State upon initialization by the controller.  
* **Conversational Search (Discovery):** The Therapist\_Search tool uses Zod schemas to extract parameters (name, specialty) from natural language. It securely hits a API endpoint  which performs a fuzzy search. The backend returns public bios and internal UUIDs. The LLM presents the bios to the user, and upon confirmation, saves the hidden UUID to the selectedTherapistId state.

## **4.2. Security & Credal Integration Specs**

* **Image-to-Text PII Masking:** When the Document\_Processor extracts text from an uploaded insurance card, it MUST be passed through Auto-Redaction. The LangGraph state and chat logs should only ever store \[INSURANCE\_ID\], never the raw numbers.  
* **Scoped Agent Actions:** The Scheduling\_Tool must not have global read/write calendar access. It must execute a scoped action that only allows GET availability and POST bookings for the specific selected TherapistId.

## **5\. Edge Cases & Exception Handling**

The LangGraph logic and backend must account for the following non-linear paths:

1. **Trauma Dumping (Token Limits):** If the user begins treating the bot as a therapist (exceeding a threshold of clinical detail), the system must gently interrupt, set boundaries, and guide them back to scheduling.  
2. **Phantom Bookings (Concurrency):** If a presented time slot is booked by another patient before the current user confirms it, the Scheduling\_Tool must catch the API conflict error, apologize to the user, and present a refreshed list of times.


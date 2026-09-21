# Product

This document defines what Morie is, what it should do, and where its product boundaries are.

Implementation belongs in `ARCHITECTURE.md` and `DEVELOPMENT.md`. UI rules belong in `DESIGN.md`. Testing and deployment belong in their respective documents.

## Product definition

Morie is an Apple-native voice input and personal context tool.

Its primary purpose is to turn a user's spoken expression into clean, natural written text with as little interruption as possible.

Over time, Morie may also learn useful personal context from intentional input so future expression can be understood more accurately.

Morie is not intended to become a general AI assistant. The core product remains **input**.

## Core experience

The primary experience is:

Speak → Recognize → Clean up and organize → Input

The interaction should feel immediate and lightweight. Morie should reduce the friction between thinking aloud and written expression.

## Voice input

Voice input is the primary interaction.

The user explicitly starts and ends a recording. Morie does not continuously listen in the background and does not treat ordinary keyboard input as voice input.

Intentional Capture may either enter text into the application currently being used or save an idea inside Morie without inserting it elsewhere.

## Recognition

Recognition converts intentional speech into text.

Its job is to represent what the user actually said as accurately as possible and may use relevant vocabulary such as names, products and technical terms.

Recognition and writing refinement are separate concerns.

## Refinement

Refinement improves expression, not content.

It may remove meaningless fillers, clear stuttering, explicit self-corrections, improve punctuation and paragraphs, organize clearly spoken enumerations, and repair obvious recognition mistakes when the intended expression is clear.

It must preserve meaning, viewpoint, tone, uncertainty, emphasis, names, terminology, numbers, conditions, negation and meaningful repetition.

It must not answer, execute, summarize into a different message, invent facts or opinions, or rewrite the user into a different personality.

Detailed refinement behavior is defined in `features/REFINEMENT.md`.

## Context

Context exists to help Morie understand the current expression.

Dictionary, Personal Memory, application context and other supporting information may help resolve ambiguity or terminology. They must not become independent sources of new expression.

The current input always has priority over historical context.

## Dictionary

Dictionary exists for words.

It helps Morie understand and preserve canonical names, terms, spellings, products, people, abbreviations and technical vocabulary.

Dictionary is not Personal Memory. It describes how something should be recognized or written, not what Morie knows about the user.

## Personal Memory

Personal Memory exists for useful context that remains valuable across interactions, such as ongoing projects, stable preferences, frequently referenced people or entities, and recurring context.

Memory should improve understanding without taking control of the user's current expression.

It must remain inspectable and controllable by the user, and normal voice input must remain useful without it.

## Learning from use

Morie may learn from the user's intentional interaction with Morie.

Learning must remain bounded to information with a clear relationship to Morie input. Morie must not become a general keyboard logger or document observer.

Background learning must never make normal voice input depend on analysis completing first.

## History

Morie keeps a useful history of intentional Captures so users can recover, inspect and reuse previous input.

History is not intended to become a general note-taking database or document management system.

## Local and external intelligence

Morie may use Apple on-device intelligence or a user-configured external compatible model.

Using an external model is an explicit user choice. Provider complexity should not leak into the ordinary product experience.

## Apple ecosystem

Morie is an Apple-platform product.

Development begins with macOS. iOS may later provide complementary capture and access to the same personal context.

The goal is not to reproduce Morie on every platform.

## Synchronization

Users may synchronize Morie data across their Apple devices using Apple-native capabilities such as iCloud when appropriate.

Cross-device synchronization is different from Morie operating its own cloud intelligence service.

## Privacy boundary

Morie processes intentional user expression and should collect only the context required for the capability being used.

It does not need to monitor everything the user types, reads or does in order to become useful.

Sending content to an external model occurs only when the user has chosen an external processing path that requires it.

## Product priorities

When goals compete, priorities are:

1. Reliable input.
2. Preserve the user's intended expression.
3. Fast interaction.
4. Natural written output.
5. Useful contextual understanding.
6. Personalization and learning.
7. Additional capabilities.

Intelligence must not make basic input unreliable. Memory must not make input slower.

## Product scope

Morie focuses on voice input, speech-to-text, expression refinement, Dictionary, Personal Memory, Capture and History, bounded learning from Morie interactions, Apple-device continuity and optional external model processing.

Morie is not currently intended to become a social product, team collaboration platform, general workspace, general-purpose AI assistant, chat product, Web application, Android application, document editor, workflow automation platform, general keyboard activity monitor or cloud knowledge-base platform.

A new capability should have a clear relationship to Morie's core input experience before it becomes part of the product.

## Product principle

Morie should make expressing something easier than fixing it afterward.

It should understand enough context to help the user express what they meant, while remaining disciplined enough not to speak for them.

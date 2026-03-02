# Checklist Question Rule Types

## Overview

Each question in a checklist is governed by a set of rules that control how it is presented to the user, what responses are accepted, and when supporting evidence (photos) is required. These rules are defined per-question at the template level and applied to every asset the question is linked to.

---

## Rule Type 1: Answer Option Type

Defines the set of choices available to the inspector when answering a question.

| Answer Type | Options | Use Case |
|---|---|---|
| **Binary** | `Yes` / `No` | Factual pass/fail condition checks |
| **Quality** | `Satisfactory` / `Unsatisfactory` | Subjective quality assessments |
| **Ternary** | `Yes` / `No` / `N/A` | Conditional checks that may not apply to every asset |

### Examples
- **Binary**: "Is the door, frame and any glazing undamaged?" → Yes / No
- **Quality**: "Are intumescent strips and smoke seals (where provided) undamaged?" → Satisfactory / Unsatisfactory
- **Ternary**: "If this door is a cupboard or riser door, is it kept locked?" → Yes / No / N/A

---

## Rule Type 2: Photo Requirement

Defines when the inspector must attach a photo to their answer. The requirement can be unconditional or triggered by the answer given.

| Photo Rule | Behaviour |
|---|---|
| **Always** | A photo is required regardless of the answer |
| **Only when negative** | A photo is required only when the answer is negative (`No` or `Unsatisfactory`) |
| **Never** *(potential)* | No photo is required (not observed in current data but may exist) |

### Negative Answer Mapping
The "Only when negative" rule depends on knowing which answer values are considered negative for each answer type:

| Answer Type | Negative Value(s) |
|---|---|
| Binary | `No` |
| Quality | `Unsatisfactory` |
| Ternary | `No` (N/A is not negative) |

---

## Rule Type 3: Asset Linkage

Each question instance is linked to a specific asset via a `Linked checklist chapter` identifier. This means:

- A **question template** defines the question text and its rules (answer type, photo requirement)
- The template is **instantiated per asset** — the same question appears once for each asset in the checklist
- Each instance carries a unique composite ID tying it to its asset

---

## Rule Type 4: Question Ordering

Questions appear in a consistent sequence per asset. The observed order is:

1. Intumescent strips and smoke seals check (Quality)
2. Door, frame and glazing condition check (Binary)
3. Cupboard/riser door locked check (Ternary)
4. Self-closing mechanism check (Binary)

This implies a **sort order** or **sequence number** rule that controls the display order of questions within an asset's checklist.

---

## Rule Type 5: Conditional Relevance

Some questions are only relevant for certain asset subtypes. For example:

> "If this door is a cupboard or riser door, is it kept locked?"

This question includes an N/A option, indicating it may not apply to all assets. This could be handled by:
- The **Ternary answer type** (allowing N/A as a valid response), or
- A **conditional visibility rule** that hides/shows the question based on asset properties

In the current data, this is handled via the N/A answer option rather than hiding the question.

---

## Summary Table

| Rule Type | What It Controls | Possible Values |
|---|---|---|
| Answer Option Type | Available response choices | Binary, Quality, Ternary |
| Photo Requirement | When a photo must be attached | Always, Only when negative, Never |
| Asset Linkage | Which asset the question belongs to | Composite ID reference |
| Question Ordering | Display sequence within an asset | Sort order / sequence number |
| Conditional Relevance | Whether the question applies | Handled via N/A option or visibility rule |

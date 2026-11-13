# Issue Resolution & Design Plan

## Goals
1. Resolve critical issues #75, #79, #77, #70, #62, #81, #80, #78.
2. Apply the newly created BRO Design System to all UI components.
3. Prioritize security, core functionality, and high-end feel.

## Issue Queue
- [ ] #79: Core Messaging — Refine UI, implement drafting and editing windows.
- [ ] #75: End-to-End Encryption — Infrastructure check.
- [ ] #77: Message Management — Edit/Delete functionality.
- [ ] #70: App Lock — Secure authentication layer.
- [ ] #62: Block/Report — Safety UI.
- [ ] #81: Prevent Screenshots — Security policy.
- [ ] #80: Emoji Reactions/Threads — Engagement.
- [ ] #78: Rich Media — File/GIF/Sticker support.

## Design Integration
- [ ] Port `Color` definitions from `_P` class in `main.dart` to use new tokens (mapped to `_P` static values).
- [ ] Refactor UI widgets (Chat bubbles, Buttons, App Bar) to use new component classes.

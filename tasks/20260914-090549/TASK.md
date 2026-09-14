# Implement the compile architecture

- STATUS: OPEN
- PRIORITY: 100
- TAGS: compile

Implement the compile architecture. For that we need some decisions.
- [ ] First, do we need something like the builder we already have?
  - [ ] So we probably need to clone the build body.
  - [ ] Then we need a Data structure that allows the required modifications (probably a Xar.)
  - [ ] How do we handle the different modifications?
- [ ] Some API for common modifications.
- [ ] Pass system.

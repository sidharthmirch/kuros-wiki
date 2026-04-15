```markdown
# kuros-wiki Development Patterns

> Auto-generated skill from repository analysis

## Overview
This skill teaches the core development patterns and conventions used in the `kuros-wiki` Swift codebase. You'll learn how to structure files, write imports and exports, follow commit message styles, and understand the approach to testing. This guide is ideal for contributors who want to maintain consistency and quality in the project.

## Coding Conventions

### File Naming
- **Convention:** PascalCase for all file names.
- **Example:**  
  `UserProfile.swift`  
  `WikiEntryManager.swift`

### Import Style
- **Convention:** Use relative imports.
- **Example:**
  ```swift
  import "../Models/UserProfile"
  ```

### Export Style
- **Convention:** Use named exports.
- **Example:**
  ```swift
  public struct WikiEntry { ... }
  ```

### Commit Messages
- **Style:** Freeform, no strict prefixes.
- **Average Length:** ~19 characters.
- **Example:**  
  `add wiki entry model`  
  `fix typo in parser`

## Workflows

### Adding a New Feature
**Trigger:** When implementing a new feature or module.  
**Command:** `/add-feature`

1. Create a new Swift file using PascalCase (e.g., `NewFeature.swift`).
2. Use relative imports to include dependencies.
3. Export new structs, classes, or functions using named exports.
4. Write a clear, concise commit message describing the feature.

### Fixing a Bug
**Trigger:** When addressing a bug in the codebase.  
**Command:** `/fix-bug`

1. Locate the relevant Swift file(s).
2. Apply the fix, following coding conventions.
3. Update or add relevant tests in `*.test.*` files.
4. Commit with a descriptive message (e.g., `fix crash on load`).

### Writing Tests
**Trigger:** When adding or updating tests.  
**Command:** `/write-test`

1. Create or update a test file matching the pattern `*.test.*` (e.g., `UserProfile.test.swift`).
2. Write test cases for your feature or bugfix.
3. Use the project's (unknown) test framework to run and verify tests.

## Testing Patterns

- **Test File Pattern:** Files should be named with `.test.` in the filename (e.g., `WikiEntry.test.swift`).
- **Framework:** Not explicitly detected; follow existing patterns in the codebase.
- **Example:**
  ```swift
  // UserProfile.test.swift
  import "../Models/UserProfile"
  // ...test cases here...
  ```

## Commands

| Command      | Purpose                                 |
|--------------|-----------------------------------------|
| /add-feature | Scaffold and commit a new feature/module|
| /fix-bug     | Apply and commit a bugfix               |
| /write-test  | Add or update tests for code changes    |
```

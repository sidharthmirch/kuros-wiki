# Who Am I

Report the active workspace profile for this folder.

## Workflow

1. Read `.claude/active-user`.
2. If the file is missing or empty, report `kuro` as the default profile.
3. Read `.wikiwise/workspace.json` and inspect `profiles`.
4. Report whether the active profile is present in the workspace profile list.
5. If the active profile is missing from `profiles`, ask the user to add it in Wikiwise settings before making attributed edits.

## Notes

- Profile IDs are workspace-scoped.
- Valid IDs use lowercase letters, numbers, hyphens, and underscores, start with a letter or number, and are at most 32 characters.
- Users can add any valid local profile, for example `sidharth` or `vidur`.

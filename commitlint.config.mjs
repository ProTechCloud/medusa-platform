export default {
	extends: ["@commitlint/config-conventional"],
	// Holds PR titles to the same rules even when they start with Revert or Merge.
	defaultIgnores: false,
};

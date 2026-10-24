/**
 * A small, representative set of tests is kept out of drilling so that sitting
 * one later still measures performance on unseen questions. Keep this list
 * deliberate: broad numeric rules can accidentally reserve most of the deck as
 * new tests are added.
 *
 * Holding them out is a default, not a rule — the settings panel can put them
 * back into drilling, which is why this list is shared by the build script and
 * the app rather than being baked into the compiled deck.
 */
export const HELD_OUT_TESTS = new Set([
  5, 12, 18, 104, 111, 119, 128, 137, 140, 146, 155, 157, 158,
])

export const isHeldOut = (test) => HELD_OUT_TESTS.has(test)

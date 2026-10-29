.pragma library

// LSAT Falcon's design tokens (src/index.css in the web app) for the
// reMarkable 2: 1404 x 1872 px at 226 dpi, portrait.
//
// Sizes are written in the web app's CSS pixels and converted with px(), at
// 2.25 device pixels each. That makes the tablet a 624 x 832 CSS-pixel
// viewport, which is narrower than the web app's `lg` breakpoint (1024) and
// `sm` (640), so the layout is its stacked, phone-width one throughout, as a
// browser held in portrait would show it.

var SCALE = 2.25;
function px(v) {
    return Math.round(v * SCALE);
}

// Colours. E-ink has no hue and fast refreshes may drop light greys, so the
// palette is rebuilt in grey with one rule: anything that carries state
// (selected, answered, correct, the primary button) is black on white or
// white on black. Greys are only ever decoration.
var surface = "#ffffff";
var surfaceSubtle = "#f4f4f4";
var inkStrong = "#000000";   // the reading ink: passage, stem, choices, explanation
var ink = "#000000";         // chrome and labels
var inkSoft = "#4d4d4d";
var inkFaint = "#7a7a7a";
var accent = "#555555";      // section headings and text links (lavender on the web)
var chip = "#e4e4e4";
var line = "#c2c2c2";
var navy = "#000000";        // filled buttons and selected chips
var correct = "#000000";
var wrong = "#000000";
var quote = "#e4e4e4";       // a passage phrase the stem quotes
var quoteStrong = "#bdbdbd";
var shareBar = "#e6e6e6";    // how the field split, behind each choice
var shareBarCorrect = "#bababa";
var white = "#ffffff";

// The reading style: --text-reading (16px, line-height 1.5). The web sets it
// at weight 375; e-ink thins strokes, so it is the regular 400 here.
var readingSize = px(16);
var readingLine = 1.5;

var lineWidth = 2;  // a 1 px CSS rule

// Tracking-tight (-0.025em) at a given size.
function tight(size) {
    return -0.025 * size;
}

// The full category taxonomy (src/categories.js).
var TAXONOMY = {
    LR: {
        label: "Logical Reasoning",
        groups: {
            Open: ["Weaken", "Strengthen", "Sufficient Assumption", "Paradox", "Evaluate", "Principle-Strengthen"],
            Closed: ["Main Conclusion", "Must be True", "Most Supported", "Must be False", "Flaw",
                     "Necessary Assumption", "Method", "Role", "Agree/Disagree", "Parallel", "Parallel Flaw",
                     "Principle-Conform"]
        }
    },
    RC: {
        label: "Reading Comprehension",
        groups: {
            Question: ["Main Point", "Primary Purpose", "Local Purpose", "Paragraph Purpose", "Organization",
                       "Locate Detail", "Inference", "Meaning in Context", "Author Opinion", "Non-Author Opinion",
                       "Author's Attitude", "Application", "Analogy", "Principle", "Method", "Strengthen", "Weaken",
                       "Evaluate", "Must be False", "Add to the Passage", "Five Questions"]
        }
    }
};

var DIFFICULTY_MAX = 5;
var DIFFICULTY_LEVELS = [1, 2, 3, 4, 5];
var SECTION_MINUTES = 35;

// The bundled Roboto instances (see tools/generate_assets.py). Every weight
// is a face of this one family, chosen with font.weight.
var font = "Falcon Roboto";

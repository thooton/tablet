.pragma library

// Colours and measurements from the "Cuentos" mockup, in reMarkable 2
// pixels (1404 x 1872).

var paper = "#f6f5f1";
var white = "#ffffff";
var ink = "#111111";
var ink2 = "#444444";
var ink3 = "#777777";
var rule = "#c9c8c3";

var screenWidth = 1404;
var screenHeight = 1872;

// Library
var headHeight = 137;        // toolbar row, including its 3 px rule
var headPad = 45;
var listMargin = 60;
var rowHeight = 190;
var rowsPerPage = 8;

// Reading
var pageLeft = 96;           // side margins; also the page-turn tap strips
var pageTop = 70;
var pageBottomStrip = 146;   // clear strip under the text: tap to show the page number
var topStrip = 150;          // tap to open the toolbar
var lineFactor = 1.8;        // 40 px text on a 72 px line pitch
var indentEm = 1.1;

// Text sizes offered in the Aa sheet (index 3 is the default 40 px), and
// the sample size each one is drawn at in the sheet.
var textSizes = [28, 32, 36, 40, 46, 54, 64];
var sampleSizes = [30, 38, 46, 56, 68, 82, 100];
var defaultTextSize = 3;

// Reading speed used for "N min restantes".
var wordsPerMinute = 120;

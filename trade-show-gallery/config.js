// Gallery settings. Edit these to tune the booth experience.
window.GALLERY_CONFIG = {
  // Filter groups shown in the sidebar, in order. "key" is the products.csv column.
  filters: [
    { key: "category", label: "Category" },
    { key: "material", label: "Material" },
    { key: "process", label: "Process" },
    { key: "finish", label: "Finish" },
    { key: "industries", label: "Industry" },
  ],

  // With only a handful of photos a sphere looks empty. While the whole catalog is
  // smaller than this, tiles are repeated to fill the sphere. Has no effect once
  // the catalog has this many products. Set to 0 to turn off.
  minTiles: 40,

  // Kiosk mode: after this many seconds without a touch, close the detail view,
  // clear search and filters, and resume spinning. Set to 0 to turn off.
  idleResetSeconds: 90,

  // Screensaver: after this many seconds without a touch, the products fly off the
  // sphere and form a clock. Any touch brings the sphere back. Set to 0 to turn off.
  screensaverSeconds: 60,

  // Clock format for the screensaver: false = 12-hour (9:41), true = 24-hour (21:41).
  clock24h: false,

  // Base spin speed in degrees per second (the sidebar slider multiplies this).
  spinDegreesPerSecond: 6,
};

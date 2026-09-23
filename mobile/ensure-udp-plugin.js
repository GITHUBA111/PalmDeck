const fs = require("fs");
const path = require("path");
const p = path.join(__dirname, "ios/App/App/capacitor.config.json");
if (!fs.existsSync(p)) process.exit(0);
const d = JSON.parse(fs.readFileSync(p, "utf8"));
const list = d.packageClassList || [];
if (!list.includes("PalmDeckUdpPlugin")) {
  d.packageClassList = ["PalmDeckUdpPlugin"];
  fs.writeFileSync(p, JSON.stringify(d, null, "\t") + "\n");
  console.log("packageClassList: added PalmDeckUdpPlugin");
} else {
  console.log("packageClassList: ok");
}
if (!(d.packageClassList || []).includes("PalmDeckUdpPlugin")) {
  console.error("release blocked: empty packageClassList");
  process.exit(1);
}

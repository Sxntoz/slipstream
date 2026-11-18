// OpenCode's background service ("serve --service") keeps running after the app closes.
const killService = () => {
  try {
    execFileSync("powershell", ["-NoProfile", "-Command", `Get-CimInstance Win32_Process -Filter "Name='opencode-cli.exe'" | Where-Object { $_.CommandLine -match 'serve --service' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }`], { windowsHide: true, timeout: 15000 })
  } catch {}
}
const restart = () => { wgStop(); killService(); app.relaunch(); app.exit(0) }
const quit = () => { wgStop(); killService(); app.exit(0) }
const later = (what) => { writeFileSync(pendingFile, JSON.stringify(what)); wgStop(); killService(); app.relaunch(); app.exit(0) }
const clearLogin = () => {
  if (!existsSync(path.join(dataDir, "auth.json"))) return say(t("noLogin"))
  later(["tokens"])
}
const restoreLogin = () => {
  if (existsSync(path.join(dataDir, "auth.json"))) return say(t("loginExists"))
  if (!newestBackup()) return say(t("noBackup"))
  later(["restore"])
}
const clearCache = () => later(["cache"])


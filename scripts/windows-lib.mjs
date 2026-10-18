import { spawn } from "node:child_process";
import { mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
export const NATIVE_SCRIPT = join(SCRIPT_DIR, "native.ps1");
export const STATE_DIR = join(tmpdir(), "opencode-cua");
export const SHOTS_DIR = join(STATE_DIR, "shots");

export function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function ensureDir(path) {
  mkdirSync(path, { recursive: true });
  return path;
}

export function runPowerShellScript(scriptPath, payload, timeoutMs = 30000) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      "powershell.exe",
      ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", scriptPath],
      { windowsHide: true }
    );
    let stdout = "";
    let stderr = "";
    let finished = false;
    const timer = setTimeout(() => {
      if (finished) return;
      finished = true;
      try {
        child.kill();
      } catch {
        // Ignore.
      }
      reject(new Error(`PowerShell automation timed out after ${timeoutMs}ms.`));
    }, timeoutMs);

    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("error", (error) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      reject(error);
    });
    child.on("close", (code) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      const text = stdout.trim();
      if (!text) {
        reject(new Error(`PowerShell automation produced no output (exit ${code}): ${stderr.trim()}`));
        return;
      }
      try {
        const result = JSON.parse(text);
        if (!result.ok) {
          const error = new Error(result?.error?.message || "PowerShell automation failed.");
          error.code = result?.error?.code || "POWERSHELL_ERROR";
          error.details = result;
          reject(error);
          return;
        }
        resolve(result);
      } catch {
        reject(
          new Error(
            `PowerShell automation returned invalid JSON (exit ${code}): ${text.slice(0, 1000)}${
              stderr ? `\n${stderr.slice(0, 1000)}` : ""
            }`
          )
        );
      }
    });
    child.stdin.end(JSON.stringify(payload));
  });
}

export function runNative(payload, timeoutMs = 30000) {
  return runPowerShellScript(NATIVE_SCRIPT, payload, timeoutMs);
}

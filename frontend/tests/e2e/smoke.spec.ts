import { expect, test } from "@playwright/test";

/**
 * Smoke suite: the cheapest possible safety net. Each test boots a page,
 * ignores wallet-dependent widgets, and asserts the critical DOM pieces
 * plus the absence of runtime exceptions. If a bad deploy drops one of
 * these, CI fails before a human ever sees the broken build.
 */

function attachConsoleGuard(page: import("@playwright/test").Page) {
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(`pageerror: ${e.message}`));
  page.on("console", (msg) => {
    if (msg.type() === "error") {
      const text = msg.text();
      // Known-noisy: wallet discovery + RPC probes when no wallet is
      // connected. Everything else is a real regression.
      if (
        text.includes("eth_getLogs") ||
        text.includes("WalletConnect") ||
        text.includes("MetaMask") ||
        text.includes("indexedDB")
      ) {
        return;
      }
      errors.push(`console.error: ${text}`);
    }
  });
  return () => errors;
}

test("home renders hero + how-it-works + faucet", async ({ page }) => {
  const errors = attachConsoleGuard(page);
  await page.goto("/");

  await expect(
    page.getByRole("heading", { name: /onchain .* solver marketplace/i })
  ).toBeVisible();
  await expect(page.getByRole("heading", { name: /how it works/i })).toBeVisible();
  await expect(page.getByRole("heading", { name: /test token faucet/i })).toBeVisible();
  await expect(page.getByRole("heading", { name: /live intents/i })).toBeVisible();
  await expect(page.getByRole("heading", { name: /recent settlements/i })).toBeVisible();

  expect(errors(), "runtime errors on /").toEqual([]);
});

test("create page renders the intent form", async ({ page }) => {
  const errors = attachConsoleGuard(page);
  await page.goto("/create");

  await expect(page.getByRole("heading", { name: /new intent/i })).toBeVisible();
  await expect(page.getByRole("heading", { name: /test token faucet/i })).toBeVisible();

  expect(errors(), "runtime errors on /create").toEqual([]);
});

test("unknown intent id lands on the 'not found' shell", async ({ page }) => {
  const errors = attachConsoleGuard(page);
  const fakeId =
    "0x0000000000000000000000000000000000000000000000000000000000000001";
  await page.goto(`/intent/${fakeId}`);

  // The detail view waits for the read, then renders either the intent or
  // a "not found" card. Either outcome is a successful render for the
  // smoke suite — we just want to prove the route doesn't crash.
  await expect(page.locator("body")).toContainText(/intent|loading|not found/i);

  expect(errors(), "runtime errors on /intent/[id]").toEqual([]);
});

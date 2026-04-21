import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";
import { Providers } from "./providers";
import { NavConnect } from "../components/NavConnect";

export const metadata: Metadata = {
  title: "IntentAuction",
  description: "Onchain competitive intent solver marketplace — Sepolia demo.",
};

// Literal access so Next inlines it into the client bundle at build time.
// If unset, the GitHub link simply doesn't render.
const GITHUB_URL = process.env.NEXT_PUBLIC_GITHUB_URL;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-ink text-zinc-100">
        <Providers>
          <header className="border-b border-surface2 bg-surface/70 backdrop-blur">
            <div className="mx-auto flex max-w-5xl items-center justify-between px-6 py-4">
              <Link href="/" className="font-mono text-lg font-semibold tracking-tight">
                intent<span className="text-accent">.auction</span>
              </Link>
              <nav className="flex items-center gap-3 text-sm">
                <Link href="/" className="hover:text-accent">
                  Feed
                </Link>
                <Link href="/create" className="hover:text-accent">
                  Create
                </Link>
                <NavConnect />
              </nav>
            </div>
          </header>
          <main className="mx-auto max-w-5xl px-6 py-10">{children}</main>
          <footer className="mt-16 border-t border-surface2 py-6 text-xs text-zinc-500">
            <div className="mx-auto flex max-w-5xl flex-col items-center justify-between gap-2 px-6 sm:flex-row">
              <span>
                IntentAuction · Sepolia demo · built with Foundry, wagmi, and viem.
              </span>
              {GITHUB_URL ? (
                <a
                  href={GITHUB_URL}
                  target="_blank"
                  rel="noreferrer"
                  className="inline-flex items-center gap-1.5 hover:text-accent"
                >
                  <GitHubIcon />
                  <span>source</span>
                </a>
              ) : null}
            </div>
          </footer>
        </Providers>
      </body>
    </html>
  );
}

function GitHubIcon() {
  return (
    <svg
      viewBox="0 0 16 16"
      width="14"
      height="14"
      fill="currentColor"
      aria-hidden="true"
    >
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8z"/>
    </svg>
  );
}

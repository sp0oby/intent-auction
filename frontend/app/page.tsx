import Link from "next/link";
import { Faucet } from "../components/Faucet";
import { IntentFeed } from "../components/IntentFeed";
import { RecentSettlements } from "../components/RecentSettlements";

export default function Page() {
  return (
    <div className="space-y-14">
      <section className="space-y-4">
        <h1 className="text-4xl font-semibold tracking-tight">
          onchain <span className="text-accent">intent</span> solver marketplace
        </h1>
        <p className="max-w-2xl text-sm leading-relaxed text-zinc-400">
          A user signs a gasless{" "}
          <span className="text-zinc-200">EIP-712</span> intent — <em>&quot;I&apos;ll send
          you 0.01 mWETH, pay me at least 1,900 mUSDC&quot;</em>. Solvers
          compete in a 12-block onchain auction to execute it for the best
          net value, committing to a target contract + calldata. After the
          window closes, anyone calls settle and the Executor runs the
          solver&apos;s calldata atomically — pull tokens, run the swap,
          verify the delivered amount beats the user&apos;s floor, split fee
          to solver. No trusted offchain relay, no custody, griefing-proof.
        </p>
        <p className="max-w-2xl text-xs leading-relaxed text-zinc-500">
          Today the demo routes swaps through{" "}
          <span className="font-mono text-zinc-300">MockSwapRouter</span>.
          The whitelisted-target design means the same auction also supports
          lending / staking / bridging intents — just whitelist the target.
        </p>
        <div className="flex flex-wrap gap-2 pt-2">
          <Link href="/create" className="btn btn-primary">
            Create intent
          </Link>
          <a
            href="https://sepolia.etherscan.io/address/0x1fD91229ee0217E9381d936Dc43d6E81283eD5c4"
            target="_blank"
            rel="noreferrer"
            className="btn btn-secondary"
          >
            Auction on Etherscan ↗
          </a>
        </div>
      </section>

      <section className="space-y-4">
        <h2 className="text-lg font-semibold tracking-tight">How it works</h2>
        <div className="grid gap-4 sm:grid-cols-3">
          <Step
            n={1}
            title="User signs"
            body="The user signs a typed Intent off-chain via EIP-712: tokenIn, amountIn, minAmountOut, maxSolverFee, deadline. Single click, no gas."
          />
          <Step
            n={2}
            title="Solvers bid"
            body="Within a 12-block window, solvers submit bids by committing to a target + calldata. Highest net value wins (outputOffered − solverFee)."
          />
          <Step
            n={3}
            title="Anyone settles"
            body="After the window closes, anyone calls settle(). The Executor runs the calldata, verifies balances atomically, pays the user and solver."
          />
        </div>
      </section>

      <section className="grid gap-6 lg:grid-cols-[1.4fr,1fr]">
        <div className="space-y-3">
          <h2 className="text-lg font-semibold tracking-tight">Try it yourself</h2>
          <p className="text-sm text-zinc-400">
            Two roles to play, both work end-to-end against the live Sepolia
            deployment. You only need <span className="text-zinc-200">Sepolia ETH</span>{" "}
            for gas — test tokens come from the faucet below.
          </p>
          <ol className="space-y-3 text-sm text-zinc-300">
            <li className="rounded border border-surface2 bg-surface/60 p-3">
              <span className="font-semibold text-accent">User ·</span>{" "}
              Mint a little mWETH, then{" "}
              <Link href="/create" className="text-accent hover:underline">
                create an intent
              </Link>
              . The app signs it (EIP-712) and posts it onchain.
            </li>
            <li className="rounded border border-surface2 bg-surface/60 p-3">
              <span className="font-semibold text-accent">Solver ·</span>{" "}
              Switch to a second wallet (or incognito + different account),
              open any intent from the feed, and place a bid. The preset
              builds calldata for you; no hex-hacking required.
            </li>
            <li className="rounded border border-surface2 bg-surface/60 p-3">
              <span className="font-semibold text-accent">Anyone ·</span>{" "}
              Wait ~12 blocks (≈2.5 min) for the auction window to end, then
              hit <span className="font-mono">Settle</span> from either
              wallet. One transaction: swap + fee split + delivery.
            </li>
          </ol>
          <p className="text-xs text-zinc-500">
            Need Sepolia ETH?{" "}
            <a
              href="https://www.alchemy.com/faucets/ethereum-sepolia"
              target="_blank"
              rel="noreferrer"
              className="text-accent hover:underline"
            >
              Alchemy Sepolia faucet
            </a>
            .
          </p>
        </div>
        <Faucet />
      </section>

      <section className="space-y-4">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-semibold tracking-tight">Live intents</h2>
          <Link href="/create" className="btn btn-secondary">
            New intent
          </Link>
        </div>
        <IntentFeed />
      </section>

      <section className="space-y-4">
        <h2 className="text-lg font-semibold tracking-tight">Recent settlements</h2>
        <RecentSettlements />
      </section>
    </div>
  );
}

function Step({ n, title, body }: { n: number; title: string; body: string }) {
  return (
    <div className="card space-y-2">
      <div className="flex items-center gap-3">
        <span className="inline-flex h-6 w-6 items-center justify-center rounded-full bg-accent/20 font-mono text-xs text-accent">
          {n}
        </span>
        <h3 className="text-sm font-semibold tracking-tight">{title}</h3>
      </div>
      <p className="text-xs leading-relaxed text-zinc-400">{body}</p>
    </div>
  );
}

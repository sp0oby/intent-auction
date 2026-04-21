import type { AbiEvent, Address, Log, PublicClient } from "viem";

/**
 * Chunked `eth_getLogs` with a GLOBAL concurrency cap.
 *
 * Alchemy's free tier caps `eth_getLogs` at a 10-block range and throttles
 * the whole key at 330 compute-units-per-second. This module-level
 * semaphore limits every caller — across components, across ticks — to
 * at most `GLOBAL_CONCURRENCY` in-flight `getLogs` requests. The viem
 * transport handles per-request retries on top of that.
 *
 * Pass `events` (plural) to match multiple event types in a single RPC
 * call per chunk — way cheaper than fetching each event type separately.
 */

const GLOBAL_CONCURRENCY = 3;
const CHUNK_SIZE = 9n;

let inflight = 0;
const queue: Array<() => void> = [];

function acquire(): Promise<void> {
  return new Promise((resolve) => {
    const tryAcquire = () => {
      if (inflight < GLOBAL_CONCURRENCY) {
        inflight++;
        resolve();
      } else {
        queue.push(tryAcquire);
      }
    };
    tryAcquire();
  });
}

function release() {
  inflight--;
  const next = queue.shift();
  if (next) next();
}

type FetchArgs = {
  client: PublicClient;
  address: Address;
  fromBlock: bigint;
  toBlock: bigint;
} & ({ event: AbiEvent; events?: undefined } | { event?: undefined; events: AbiEvent[] });

export async function fetchLogsChunked(args: FetchArgs): Promise<Log[]> {
  const { client, address, fromBlock, toBlock } = args;
  const ranges: Array<{ from: bigint; to: bigint }> = [];
  for (let start = fromBlock; start <= toBlock; start += CHUNK_SIZE + 1n) {
    const end = start + CHUNK_SIZE > toBlock ? toBlock : start + CHUNK_SIZE;
    ranges.push({ from: start, to: end });
  }

  const results = await Promise.all(
    ranges.map(async (r) => {
      await acquire();
      try {
        if (args.events) {
          return await client.getLogs({
            address,
            events: args.events,
            fromBlock: r.from,
            toBlock: r.to,
          });
        }
        return await client.getLogs({
          address,
          event: args.event,
          fromBlock: r.from,
          toBlock: r.to,
        });
      } finally {
        release();
      }
    })
  );

  return results.flat();
}

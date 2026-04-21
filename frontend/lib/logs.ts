import type { AbiEvent, Address, Log, PublicClient } from "viem";

/**
 * Chunked `eth_getLogs` with a GLOBAL concurrency cap.
 *
 * Alchemy's free tier caps `eth_getLogs` at a 10-block range and throttles
 * the whole key at 330 compute-units-per-second. With two independent feed
 * components firing at the same time each was launching 6 parallel chunks,
 * which trivially blew past the CU/s cap and surfaced 429s.
 *
 * This module-level semaphore limits every caller — across components, across
 * ticks — to at most `GLOBAL_CONCURRENCY` in-flight `getLogs` requests. The
 * viem transport handles per-request retries; this guards against stampeding
 * many concurrent requests in the first place.
 */

const GLOBAL_CONCURRENCY = 2;
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

export async function fetchLogsChunked({
  client,
  address,
  event,
  fromBlock,
  toBlock,
}: {
  client: PublicClient;
  address: Address;
  event: AbiEvent;
  fromBlock: bigint;
  toBlock: bigint;
}): Promise<Log[]> {
  const ranges: Array<{ from: bigint; to: bigint }> = [];
  for (let start = fromBlock; start <= toBlock; start += CHUNK_SIZE + 1n) {
    const end = start + CHUNK_SIZE > toBlock ? toBlock : start + CHUNK_SIZE;
    ranges.push({ from: start, to: end });
  }

  const results = await Promise.all(
    ranges.map(async (r) => {
      await acquire();
      try {
        return await client.getLogs({
          address,
          event,
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

import { test, expect } from "bun:test";
import { VirtualRequestQueue } from "../src/virtual-request-queue.ts";

for (const method of ["computer.click", "computer.typeText"]) {
  test("slow observe expires queued " + method + "; retry executes exactly once", async () => {
    let release!: () => void, now = 0;
    const blocked = new Promise<void>(r => release = r);
    const inputs: string[] = [], replies: any[] = [];
    const queue = new VirtualRequestQueue(async method => {
      if (method === "computer.observe") await blocked;
      else inputs.push(method);
      return { ok: true };
    }, reply => replies.push(reply), () => now);
    const observation = queue.enqueue({id: 1, method: "computer.observe", deadline: 100});
    await Promise.resolve();
    const expired = queue.enqueue({id: 2, method, deadline: 10});
    now = 11;
    release(); await observation; await expired;
    expect(inputs).toEqual([]);
    expect(replies.find(r => r.id === 2)?.outcome).toBe("cancelled");
    await queue.enqueue({id: 3, method, deadline: 30});
    expect(inputs).toEqual([method]);
  });
}
test("cancel and stop acknowledge unstarted work separately from uncertain started work", async () => {
  let release!: () => void;
  const blocked = new Promise<void>(r => release = r);
  const replies: any[] = [], calls: string[] = [];
  const queue = new VirtualRequestQueue(async method => { calls.push(method); await blocked; }, r => replies.push(r));
  const started = queue.enqueue({id: 1, method: "computer.click", deadline: Date.now() + 1000});
  await Promise.resolve();
  const queued = queue.enqueue({id: 2, method: "computer.typeText", deadline: Date.now() + 1000});
  queue.stop();
  expect(replies.find(r => r.id === 1 && r.error)?.outcome).toBe("uncertain");
  expect(replies.find(r => r.id === 2)?.outcome).toBe("cancelled");
  release(); await started; await queued;
  expect(calls).toEqual(["computer.click"]);
  expect(replies.filter(r => r.id === 1 && r.error)).toHaveLength(1);
});

#!/usr/bin/env node
/**
 * End-to-end smoke test against a running ShopStream gateway.
 *
 *   GATEWAY_URL=http://localhost:4780/graphql node scripts/smoke-test.mjs
 *
 * (copied from github.com/lalitkumarrajak/shopstream/scripts/smoke.mjs — dependency-free Node 20+)
 *
 * 1. waits for the gateway (handles free-tier cold starts)
 * 2. signs in as the demo user
 * 3. happy path: checkout with 4242… and wait for CONFIRMED (payment + stock)
 * 4. saga compensation: checkout with 4000…0002 and wait for CANCELLED with
 *    payment FAILED, inventory RELEASED and the stock back where it was
 */
const GATEWAY_URL = process.env.GATEWAY_URL ?? 'http://localhost:4780/graphql';
const HOST_HEADER = process.env.SMOKE_HOST_HEADER; // e.g. for ingress testing via an IP
const WAIT_MS = Number(process.env.SMOKE_WAIT_MS ?? 180_000);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (msg) => console.log(`[smoke] ${msg}`);
let token;

async function gql(query, variables = {}) {
  const res = await fetch(GATEWAY_URL, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(HOST_HEADER ? { host: HOST_HEADER } : {}),
    },
    body: JSON.stringify({ query, variables }),
  });
  const body = await res.json();
  if (body.errors?.length) throw new Error(`GraphQL error: ${JSON.stringify(body.errors)}`);
  return body.data;
}

async function waitForGateway() {
  const deadline = Date.now() + WAIT_MS;
  for (let i = 1; ; i++) {
    try {
      // Through the ingress only /graphql and /events reach the gateway.
      const res = await fetch(GATEWAY_URL, {
        method: 'POST',
        headers: { 'content-type': 'application/json', ...(HOST_HEADER ? { host: HOST_HEADER } : {}) },
        body: JSON.stringify({ query: '{ __typename }' }),
      });
      if (res.ok) return;
    } catch {
      /* not up yet */
    }
    if (Date.now() > deadline) throw new Error(`gateway not ready after ${WAIT_MS}ms`);
    if (i % 5 === 1) log('waiting for the gateway to become ready…');
    await sleep(2_000);
  }
}

async function waitFor(desc, fn, timeoutMs = 60_000) {
  const deadline = Date.now() + timeoutMs;
  let last;
  while (Date.now() < deadline) {
    last = await fn();
    if (last.done) return last.value;
    await sleep(500);
  }
  throw new Error(`timed out waiting for ${desc}; last state: ${JSON.stringify(last?.value)}`);
}

const ORDER_FIELDS = `id number status paymentStatus inventoryStatus total { formatted }
  payment { status attempts } timeline { type title }`;

async function availability(productId) {
  const d = await gql(`query($id: ID!) { product(id: $id) { available } }`, { id: productId });
  return d.product.available;
}

async function checkout(productId, cardNumber, label) {
  await gql(`mutation { clearCart { itemCount } }`);
  await gql(`mutation($id: ID!) { addToCart(productId: $id, quantity: 1) { itemCount } }`, { id: productId });
  const d = await gql(`mutation($input: CheckoutInput!) { checkout(input: $input) { ${ORDER_FIELDS} } }`, {
    input: {
      cardNumber,
      cardExpiry: '12/34',
      cardCvc: '123',
      idempotencyKey: `smoke-${label}-${Date.now()}`,
      shippingAddress: {
        name: 'Smoke Test',
        line1: '1 Test Street',
        city: 'Pune',
        postalCode: '411001',
        country: 'IN',
      },
    },
  });
  log(`${label}: placed ${d.checkout.number} (${d.checkout.total.formatted}) -> ${d.checkout.status}`);
  return d.checkout;
}

const getOrder = async (id) =>
  (await gql(`query($id: ID!) { order(id: $id) { ${ORDER_FIELDS} } }`, { id })).order;

async function main() {
  log(`gateway: ${GATEWAY_URL}`);
  await waitForGateway();
  const login = await gql(`mutation { demoLogin { token user { email } } }`);
  token = login.demoLogin.token;
  log(`signed in as ${login.demoLogin.user.email}`);

  // Wait until the orders service has the catalog replica (first boot).
  const product = await waitFor('an in-stock product in the cart replica', async () => {
    const d = await gql(
      `{ products(first: 20, sort: PRICE_ASC, filter: { inStockOnly: true }) { edges { node { id name available } } } }`,
    );
    const candidate = d.products.edges.map((e) => e.node).find((p) => p.available > 3);
    if (!candidate) return { done: false };
    try {
      await gql(`mutation($id: ID!) { addToCart(productId: $id, quantity: 1) { itemCount } }`, {
        id: candidate.id,
      });
      return { done: true, value: candidate };
    } catch {
      return { done: false, value: 'replica not ready' };
    }
  });
  log(`using product "${product.name}"`);

  // 1) happy path
  const ok = await checkout(product.id, '4242424242424242', 'happy-path');
  const confirmed = await waitFor('order CONFIRMED', async () => {
    const o = await getOrder(ok.id);
    return { done: ['CONFIRMED', 'SHIPPED', 'DELIVERED'].includes(o.status), value: o };
  });
  if (confirmed.paymentStatus !== 'SUCCEEDED')
    throw new Error(`expected payment SUCCEEDED, got ${confirmed.paymentStatus}`);
  if (!['RESERVED', 'COMMITTED'].includes(confirmed.inventoryStatus))
    throw new Error(`unexpected inventory ${confirmed.inventoryStatus}`);
  log(
    `happy-path: ${confirmed.number} is ${confirmed.status} (payment ${confirmed.paymentStatus}, stock ${confirmed.inventoryStatus}) ✔`,
  );

  // 2) declined card -> compensation
  const before = await availability(product.id);
  const bad = await checkout(product.id, '4000000000000002', 'declined-card');
  const cancelled = await waitFor('order CANCELLED + stock RELEASED', async () => {
    const o = await getOrder(bad.id);
    return { done: o.status === 'CANCELLED' && o.inventoryStatus === 'RELEASED', value: o };
  });
  if (cancelled.paymentStatus !== 'FAILED')
    throw new Error(`expected payment FAILED, got ${cancelled.paymentStatus}`);
  const after = await availability(product.id);
  if (after !== before) throw new Error(`stock not restored: before=${before} after=${after}`);
  log(
    `declined-card: ${cancelled.number} is CANCELLED, payment FAILED, stock released (${before} -> ${after}) ✔`,
  );
  log(`timeline: ${cancelled.timeline.map((t) => t.title).join(' → ')}`);
  log('ALL GOOD');
}

main().catch((err) => {
  console.error(`[smoke] FAILED: ${err.message}`);
  process.exit(1);
});

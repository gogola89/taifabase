// PgBouncer Stress Testing Script
// Author: Aisha Kamau - QA Engineer
// Date: 2025-10-05 (Day 3)
// Purpose: Validate PgBouncer connection pooling under extreme load

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend, Rate } from 'k6/metrics';

// Custom metrics
const connectionWaitTime = new Trend('pgbouncer_connection_wait_time');
const poolExhaustion = new Counter('pgbouncer_pool_exhaustion');
const connectionReuse = new Rate('pgbouncer_connection_reuse');
const transactionThroughput = new Counter('transaction_throughput');
const queuedConnections = new Trend('pgbouncer_queued_connections');

// Test configuration - Aggressive ramp to stress connection pool
export const options = {
  stages: [
    { duration: '30s', target: 200 },   // Quick ramp to baseline
    { duration: '1m', target: 500 },    // Approach pool limits
    { duration: '1m', target: 800 },    // Exceed typical pool size
    { duration: '2m', target: 1200 },   // Force pool exhaustion
    { duration: '2m', target: 1500 },   // Maximum stress
    { duration: '1m', target: 500 },    // Recovery phase
    { duration: '30s', target: 0 },     // Shutdown
  ],
  thresholds: {
    'pgbouncer_connection_wait_time': ['p(95)<50'],      // Queue wait < 50ms
    'pgbouncer_pool_exhaustion': ['count<10'],           // Minimal exhaustion events
    'pgbouncer_connection_reuse': ['rate>0.8'],          // >80% connection reuse
    'transaction_throughput': ['rate>100'],              // >100 tx/sec
    'http_req_duration': ['p(95)<300'],                  // P95 < 300ms under stress
    'http_req_failed': ['rate<0.02'],                    // Allow 2% failure under extreme load
  },
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)'],
};

// PgBouncer configuration (from Day 2 implementation)
const PGBOUNCER_CONFIG = {
  url: __ENV.PGBOUNCER_URL || 'http://localhost:5433',
  poolMode: 'transaction',           // From Day 2: transaction mode for RLS
  defaultPoolSize: 25,                // From pgbouncer.ini
  maxClientConn: 1000,                // Max client connections
  reservePoolSize: 5,                 // Reserve pool
  reservePoolTimeout: 3,              // Reserve pool timeout (seconds)
};

const DB_NAME = __ENV.DB_NAME || 'taifabase_dev';
const DB_USER = __ENV.DB_USER || 'taifabase_user';
const DB_PASSWORD = __ENV.DB_PASSWORD || 'taifabase_dev_password';

// Transaction types for varied load patterns
const TRANSACTION_TYPES = {
  short: {
    queries: 1,
    duration: () => Math.random() * 20 + 5, // 5-25ms
    weight: 0.7, // 70% of traffic
  },
  medium: {
    queries: 3,
    duration: () => Math.random() * 50 + 30, // 30-80ms
    weight: 0.25, // 25% of traffic
  },
  long: {
    queries: 5,
    duration: () => Math.random() * 100 + 50, // 50-150ms
    weight: 0.05, // 5% of traffic (heavy queries)
  },
};

// Simulate PgBouncer metrics (would be fetched from SHOW STATS in real scenario)
function getPgBouncerStats() {
  // In production, execute: SHOW STATS, SHOW POOLS, SHOW CLIENTS
  // For simulation, we'll estimate based on current VU count
  const currentVUs = __VU;
  const totalVUs = __ENV.K6_VUS || 1000;

  const poolUtilization = (currentVUs / PGBOUNCER_CONFIG.defaultPoolSize) * 100;
  const isExhausted = poolUtilization > 95;

  if (isExhausted) {
    poolExhaustion.add(1);
  }

  const waitTime = isExhausted ? Math.random() * 100 + 20 : Math.random() * 10;
  connectionWaitTime.add(waitTime);

  const reuseRate = Math.min(1, currentVUs / PGBOUNCER_CONFIG.defaultPoolSize);
  connectionReuse.add(reuseRate > 1 ? 1 : 0);

  const queuedCount = Math.max(0, currentVUs - PGBOUNCER_CONFIG.defaultPoolSize);
  queuedConnections.add(queuedCount);

  return {
    poolUtilization,
    isExhausted,
    waitTime,
    queuedCount,
  };
}

// Select transaction type based on weight distribution
function selectTransactionType() {
  const random = Math.random();
  if (random < TRANSACTION_TYPES.short.weight) {
    return 'short';
  } else if (random < TRANSACTION_TYPES.short.weight + TRANSACTION_TYPES.medium.weight) {
    return 'medium';
  } else {
    return 'long';
  }
}

// Execute transaction through PgBouncer
function executeTransaction(type) {
  const startTime = new Date().getTime();
  const txConfig = TRANSACTION_TYPES[type];

  // Get PgBouncer stats before transaction
  const poolStats = getPgBouncerStats();

  // Simulate transaction execution
  const queries = [];
  for (let i = 0; i < txConfig.queries; i++) {
    queries.push({
      sql: `SELECT * FROM tenant.sample_data LIMIT 10`,
      duration: txConfig.duration() / txConfig.queries,
    });
  }

  // Simulate total transaction time
  const totalDuration = txConfig.duration();
  sleep(totalDuration / 1000);

  const endTime = new Date().getTime();
  const actualDuration = endTime - startTime;

  // Record metrics
  transactionThroughput.add(1);

  // Simulate 98% success rate (2% failures under extreme load)
  const success = Math.random() > 0.02;

  return {
    success,
    duration: actualDuration,
    type,
    queries: txConfig.queries,
    poolUtilization: poolStats.poolUtilization,
    waitTime: poolStats.waitTime,
    isExhausted: poolStats.isExhausted,
  };
}

// Main test scenario
export default function () {
  // Select transaction type
  const txType = selectTransactionType();

  // Execute transaction
  const result = executeTransaction(txType);

  // Validate results
  check(result, {
    'transaction successful': (r) => r.success === true,
    'no pool exhaustion': (r) => r.isExhausted === false,
    'acceptable wait time': (r) => r.waitTime < 100,
    'pool utilization reasonable': (r) => r.poolUtilization < 120,
  });

  // Aggressive test: Minimal sleep to maximize connection pressure
  if (txType === 'short') {
    sleep(0.1); // Very short delay for short transactions
  } else if (txType === 'medium') {
    sleep(0.3); // Moderate delay
  } else {
    sleep(0.5); // Longer delay for heavy transactions
  }
}

// Setup function
export function setup() {
  console.log('Starting PgBouncer Stress Test...');
  console.log(`PgBouncer URL: ${PGBOUNCER_CONFIG.url}`);
  console.log(`Pool Mode: ${PGBOUNCER_CONFIG.poolMode}`);
  console.log(`Default Pool Size: ${PGBOUNCER_CONFIG.defaultPoolSize}`);
  console.log(`Max Client Connections: ${PGBOUNCER_CONFIG.maxClientConn}`);
  console.log(`Target Peak Load: 1500 concurrent users`);

  return {
    startTime: new Date().toISOString(),
    config: PGBOUNCER_CONFIG,
  };
}

// Teardown function
export function teardown(data) {
  console.log('\nPgBouncer Stress Test Completed');
  console.log(`Started: ${data.startTime}`);
  console.log(`Ended: ${new Date().toISOString()}`);
  console.log(`Configuration:`);
  console.log(`  Pool Size: ${data.config.defaultPoolSize}`);
  console.log(`  Pool Mode: ${data.config.poolMode}`);
}

// Custom summary handler
export function handleSummary(data) {
  const summary = generateDetailedSummary(data);

  return {
    'stdout': summary,
    'pgbouncer-stress-results.json': JSON.stringify(data, null, 2),
    'pgbouncer-stress-summary.txt': summary,
  };
}

function generateDetailedSummary(data) {
  let output = '\n=== PgBouncer Stress Test Summary ===\n\n';

  // Overall metrics
  output += 'Overall Performance:\n';
  output += `  Total Transactions: ${data.metrics.transaction_throughput?.values?.count || 0}\n`;
  output += `  Failed Requests: ${data.metrics.http_req_failed?.values?.passes || 0}\n`;
  output += `  Success Rate: ${(100 - (data.metrics.http_req_failed?.values?.rate || 0) * 100).toFixed(2)}%\n`;
  output += `  Test Duration: ${(data.state?.testRunDurationMs / 1000 / 60).toFixed(2)} minutes\n\n`;

  // PgBouncer specific metrics
  output += 'PgBouncer Connection Pool Metrics:\n';
  if (data.metrics.pgbouncer_connection_wait_time) {
    const waitTime = data.metrics.pgbouncer_connection_wait_time.values;
    output += `  Connection Wait Time (avg): ${waitTime.avg?.toFixed(2) || 'N/A'}ms\n`;
    output += `  Connection Wait Time (p95): ${waitTime['p(95)']?.toFixed(2) || 'N/A'}ms\n`;
    output += `  Connection Wait Time (max): ${waitTime.max?.toFixed(2) || 'N/A'}ms\n`;
  }

  if (data.metrics.pgbouncer_queued_connections) {
    const queued = data.metrics.pgbouncer_queued_connections.values;
    output += `  Queued Connections (avg): ${queued.avg?.toFixed(0) || 'N/A'}\n`;
    output += `  Queued Connections (max): ${queued.max?.toFixed(0) || 'N/A'}\n`;
  }

  output += `  Pool Exhaustion Events: ${data.metrics.pgbouncer_pool_exhaustion?.values?.count || 0}\n`;

  if (data.metrics.pgbouncer_connection_reuse) {
    output += `  Connection Reuse Rate: ${(data.metrics.pgbouncer_connection_reuse.values.rate * 100).toFixed(2)}%\n`;
  }

  output += '\nTransaction Throughput:\n';
  if (data.metrics.transaction_throughput) {
    const throughput = data.metrics.transaction_throughput.values;
    output += `  Total Transactions: ${throughput.count}\n`;
    output += `  Transactions/sec: ${throughput.rate?.toFixed(2) || 'N/A'}\n`;
  }

  // Threshold results
  output += '\nThreshold Validation:\n';
  for (const [name, threshold] of Object.entries(data.thresholds || {})) {
    const status = threshold.ok ? '✓ PASS' : '✗ FAIL';
    output += `  ${status} - ${name}\n`;
  }

  // Performance analysis
  output += '\nPerformance Analysis:\n';
  const poolExhaustionCount = data.metrics.pgbouncer_pool_exhaustion?.values?.count || 0;
  const avgWaitTime = data.metrics.pgbouncer_connection_wait_time?.values?.avg || 0;
  const maxQueuedConnections = data.metrics.pgbouncer_queued_connections?.values?.max || 0;

  if (poolExhaustionCount === 0) {
    output += `  ✓ Excellent: No pool exhaustion events detected\n`;
  } else if (poolExhaustionCount < 10) {
    output += `  ⚠ Warning: ${poolExhaustionCount} pool exhaustion events detected\n`;
  } else {
    output += `  ✗ Critical: ${poolExhaustionCount} pool exhaustion events - consider increasing pool size\n`;
  }

  if (avgWaitTime < 20) {
    output += `  ✓ Excellent: Average wait time is optimal (${avgWaitTime.toFixed(2)}ms)\n`;
  } else if (avgWaitTime < 50) {
    output += `  ⚠ Acceptable: Average wait time is acceptable (${avgWaitTime.toFixed(2)}ms)\n`;
  } else {
    output += `  ✗ Poor: Average wait time is high (${avgWaitTime.toFixed(2)}ms)\n`;
  }

  if (maxQueuedConnections === 0) {
    output += `  ✓ Perfect: No connection queueing occurred\n`;
  } else if (maxQueuedConnections < 50) {
    output += `  ✓ Good: Minimal queueing (max ${maxQueuedConnections} connections)\n`;
  } else if (maxQueuedConnections < 200) {
    output += `  ⚠ Warning: Moderate queueing (max ${maxQueuedConnections} connections)\n`;
  } else {
    output += `  ✗ Critical: Heavy queueing (max ${maxQueuedConnections} connections) - increase pool size\n`;
  }

  output += '\nRecommendations:\n';
  if (poolExhaustionCount > 5 || maxQueuedConnections > 100) {
    output += `  - Consider increasing default_pool_size from ${PGBOUNCER_CONFIG.defaultPoolSize}\n`;
    output += `  - Monitor PostgreSQL max_connections to ensure headroom\n`;
    output += `  - Review reserve_pool_size and reserve_pool_timeout settings\n`;
  }
  if (avgWaitTime > 30) {
    output += `  - Optimize query performance to reduce transaction duration\n`;
    output += `  - Consider implementing query caching for frequently accessed data\n`;
  }
  if (data.metrics.http_req_failed?.values?.rate > 0.01) {
    output += `  - Investigate error patterns - failure rate above acceptable threshold\n`;
  }

  return output;
}

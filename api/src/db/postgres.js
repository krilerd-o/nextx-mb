const { Pool } = require('pg');

let pool;
let ready = false;

function initPg() {
  const maxConnections = parseInt(
    process.env.PG_POOL_SIZE || process.env.DB_POOL_SIZE || '50',
    10,
  );
  pool = new Pool({
    host: process.env.PG_HOST || process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.PG_PORT || process.env.DB_PORT || '5432', 10),
    database: process.env.PG_DATABASE || process.env.DB_NAME || 'db_moai_next',
    user: process.env.PG_USER || process.env.DB_USER || 'postgres',
    password: process.env.PG_PASSWORD || process.env.DB_PASSWORD || 'postgres',
    max: maxConnections,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: parseInt(process.env.DB_CONNECT_TIMEOUT || '10000', 10),
  });
  return pool.query('SELECT 1').then(() => { ready = true; });
}

function isPgReady() {
  return !!pool && ready;
}

function queryPg(text, params) {
  if (!pool) throw new Error('PostgreSQL not initialized');
  return pool.query(text, params);
}

module.exports = { initPg, queryPg, isPgReady };

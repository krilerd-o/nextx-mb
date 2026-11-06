const { MongoClient } = require('mongodb');

let client;
let db;
let ready = false;

async function initMongo() {
  const uri = process.env.MONGODB_URI || process.env.MONGO_URI || 'mongodb://localhost:27017';
  const dbName = process.env.MONGODB_DB_NAME || process.env.MONGO_DB || 'nextx';
  const maxPoolSize = parseInt(process.env.MONGO_POOL_SIZE || '100', 10);
  client = new MongoClient(uri, { maxPoolSize });
  await client.connect();
  db = client.db(dbName);
  await db.command({ ping: 1 });
  ready = true;
}

function isMongoReady() {
  return !!db && ready;
}

function getMongoDb() {
  if (!db) throw new Error('MongoDB not initialized');
  return db;
}

module.exports = { initMongo, getMongoDb, isMongoReady };

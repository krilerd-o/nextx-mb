const MODULE_REGISTRY = {
  users: { table: 'aicrm_users', idColumn: 'id', businessColumn: 'business_id' },
  business: { table: 'aicrm_business', idColumn: 'id', businessColumn: 'id' },
  leads: { table: 'aicrm_leads', idColumn: 'id', businessColumn: 'business_id' },
  contacts: { table: 'aicrm_contacts', idColumn: 'id', businessColumn: 'business_id' },
  tasks: { table: 'aicrm_tasks', idColumn: 'id', businessColumn: 'business_id' },
};

function listModules() {
  return Object.keys(MODULE_REGISTRY).map((key) => ({
    module: key,
    table: MODULE_REGISTRY[key].table,
  }));
}

function getModuleConfig(moduleName) {
  return MODULE_REGISTRY[moduleName] || null;
}

module.exports = { MODULE_REGISTRY, listModules, getModuleConfig };

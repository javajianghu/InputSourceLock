#!/usr/bin/env node
// Architecture structural analyzer (deterministic pass for this project)
const fs = require('fs');

const input = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const fileNodes = input.fileNodes;
const allEdges = input.allEdges;

const directoryGroups = {};
const nodeTypeGroups = {};
const patternMatches = {};

const patternMap = {
  routes: 'api', api: 'api', controllers: 'api', endpoints: 'api', handlers: 'api',
  services: 'service', core: 'service', lib: 'service', domain: 'service', logic: 'service',
  models: 'data', db: 'data', data: 'data', persistence: 'data', repository: 'data', entities: 'data',
  components: 'ui', views: 'ui', pages: 'ui', ui: 'ui', layouts: 'ui', screens: 'ui',
  middleware: 'middleware', plugins: 'middleware', interceptors: 'middleware', guards: 'middleware',
  utils: 'utility', helpers: 'utility', common: 'utility', shared: 'utility', tools: 'utility',
  config: 'config', constants: 'config', env: 'config', settings: 'config',
  tests: 'test', test: 'test', __tests__: 'test', specs: 'test',
  types: 'types', interfaces: 'types', schemas: 'types', contracts: 'types', dtos: 'types',
  docs: 'documentation', documentation: 'documentation', wiki: 'documentation',
  deploy: 'infrastructure', deployment: 'infrastructure', infra: 'infrastructure', infrastructure: 'infrastructure',
  '.github': 'ci-cd', '.gitlab': 'ci-cd', '.circleci': 'ci-cd',
  k8s: 'infrastructure', kubernetes: 'infrastructure', helm: 'infrastructure', charts: 'infrastructure',
  terraform: 'infrastructure', tf: 'infrastructure', docker: 'infrastructure',
  sql: 'data', database: 'data', migrations: 'data',
};

fileNodes.forEach(n => {
  const fp = n.filePath || n.id.replace(/^[^:]+:/, '');
  const parts = fp.split('/');
  // group: top-level dir after common prefix
  let group;
  if (parts.length === 1) group = '<root>';
  else group = parts[0];

  if (!directoryGroups[group]) directoryGroups[group] = [];
  directoryGroups[group].push(n.id);

  if (!nodeTypeGroups[n.type]) nodeTypeGroups[n.type] = [];
  nodeTypeGroups[n.type].push(n.id);

  // pattern match by dir name or filename
  if (parts.length > 1 && patternMap[parts[0]]) {
    patternMatches[parts[0]] = patternMap[parts[0]];
  }
  const base = parts[parts.length - 1];
  if (base === 'Dockerfile' || base.match(/docker-compose/)) patternMatches[fp] = 'infrastructure';
  if (fp.match(/\.github\/workflows/)) patternMatches[fp] = 'ci-cd';
  if (fp.match(/\.gitlab-ci/)) patternMatches[fp] = 'ci-cd';
  if (base === 'README.md' || fp.endsWith('.md')) patternMatches[fp] = 'documentation';
  if (base.match(/Cargo\.toml|go\.mod|Gemfile|pom\.xml|build\.gradle|composer\.json|package\.json|pyproject\.toml/)) patternMatches[fp] = 'config';
  if (fp.match(/\.tf$|\.tfvars$/)) patternMatches[fp] = 'infrastructure';
  if (fp.match(/\.sql$/)) patternMatches[fp] = 'data';
  if (fp.match(/\.graphql$|\.proto$|\.prisma$/)) patternMatches[fp] = 'types';
  if (base === 'main.swift' || base === 'main.go' || base === 'main.py') patternMatches[fp] = 'entry';
  if (fp.includes('Info.plist')) patternMatches[fp] = 'config';
});

const crossCategoryEdges = {};
allEdges.forEach(e => {
  const src = fileNodes.find(n => n.id === e.source);
  const tgt = fileNodes.find(n => n.id === e.target);
  if (!src || !tgt) return;
  const key = `${src.type}->${tgt.type}:${e.type}`;
  crossCategoryEdges[key] = (crossCategoryEdges[key] || 0) + 1;
});

const interGroupImports = {};
allEdges.forEach(e => {
  if (e.type !== 'imports' && e.type !== 'depends_on') return;
  const src = fileNodes.find(n => n.id === e.source);
  const tgt = fileNodes.find(n => n.id === e.target);
  if (!src || !tgt) return;
  const srcPath = src.filePath || src.id.replace(/^[^:]+:/, '');
  const tgtPath = tgt.filePath || tgt.id.replace(/^[^:]+:/, '');
  const sGrp = srcPath.includes('/') ? srcPath.split('/')[0] : '<root>';
  const tGrp = tgtPath.includes('/') ? tgtPath.split('/')[0] : '<root>';
  if (sGrp === tGrp) return;
  const k = `${sGrp}->${tGrp}`;
  interGroupImports[k] = (interGroupImports[k] || 0) + 1;
});

const output = {
  scriptCompleted: true,
  directoryGroups,
  nodeTypeGroups,
  patternMatches,
  crossCategoryEdges,
  interGroupImports,
  fileStats: {
    totalFileNodes: fileNodes.length,
    filesPerGroup: Object.fromEntries(Object.entries(directoryGroups).map(([k,v]) => [k, v.length])),
    nodeTypeCounts: Object.fromEntries(Object.entries(nodeTypeGroups).map(([k,v]) => [k, v.length]))
  }
};

fs.writeFileSync(process.argv[3], JSON.stringify(output, null, 2));
console.log("Wrote", process.argv[3]);
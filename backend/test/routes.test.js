import { test } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { createRoute } from '../src/admin-routes.js';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
export const routeInput={origin:'Boac',destination:'Gasan',active:true,displayName:null,description:null,originTerminal:null,destinationTerminal:null,boardingNotes:null,administrativeNotes:null,operationsVerified:false};
test('route validation rejects invalid directions, long fields and mass assignment',()=>{
  assert.ok(createRoute.safeParse(routeInput).success);
  for(const patch of [{destination:'Boac'},{origin:'Unknown'},{id:'chosen'},{originTerminal:'x'.repeat(201)},{boardingNotes:'line\nbreak'},{active:'yes'},{latitude:13}])assert.equal(createRoute.safeParse({...routeInput,...patch}).success,false);
});
test('route writes require an administrator and trusted origin; failures are sanitized',async()=>{
  const config=loadConfig({DATABASE_URL:'postgresql://unused@127.0.0.1/unused'});
  const app=createApp({config,adminRepository:{session:async()=>({id:'admin',role:'ADMIN',expires_at:new Date(Date.now()+60000)})},adminRouteRepository:{create:async()=>{throw new Error('private SQL');}}});
  for(const [method,path] of [['post','/routes'],['put','/routes/00000000-0000-4000-8000-000000000000'],['post','/routes/00000000-0000-4000-8000-000000000000/activation']]) {
    await request(app)[method]('/api/admin'+path).set('Origin',config.ADMIN_WEB_ORIGINS).set('X-AbangQue-Admin','1').set('Authorization','Bearer passenger').send(routeInput).expect(401);
    await request(app)[method]('/api/admin'+path).send(routeInput).expect(403);
  }
  const result=await request(app).post('/api/admin/routes').set('Cookie','abangque_admin=aqa_'+'x'.repeat(43)).set('Origin',config.ADMIN_WEB_ORIGINS).set('X-AbangQue-Admin','1').send(routeInput).expect(503);
  assert.deepEqual(result.body,{error:'SERVICE_UNAVAILABLE'});
});

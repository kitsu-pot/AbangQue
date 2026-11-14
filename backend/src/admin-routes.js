import { Router,json } from 'express';
import { rateLimit } from 'express-rate-limit';
import { z } from 'zod';
export const municipalities=['Boac','Mogpog','Gasan','Buenavista','Santa Cruz','Torrijos'];
const text=max=>z.string().trim().max(max).refine(v=>!/[\u0000-\u001f\u007f]/u.test(v),'Use plain text without control characters.').nullable();
const metadata={displayName:text(120),description:text(1000),originTerminal:text(200),destinationTerminal:text(200),boardingNotes:text(1000),administrativeNotes:text(2000),operationsVerified:z.boolean()};
export const createRoute=z.object({origin:z.enum(municipalities),destination:z.enum(municipalities),active:z.boolean(),...metadata}).strict().refine(v=>v.origin!==v.destination,{path:['destination'],message:'Choose a different destination.'});
const version=z.number().int().positive().max(2147483646);
const edit=z.object({...metadata,expectedVersion:version}).strict();
const activation=z.object({active:z.boolean(),expectedVersion:version}).strict();
const paging={page:z.coerce.number().int().min(1).max(100000).default(1),pageSize:z.coerce.number().int().min(1).max(100).default(20)};
const query=z.object({search:z.string().trim().max(120).default(''),municipality:z.enum(['all',...municipalities]).default('all'),status:z.enum(['all','active','inactive']).default('all'),...paging}).strict();
const validate=(schema,source='body')=>(req,res,next)=>{const p=schema.safeParse(req[source]); if(!p.success)return res.status(400).json({error:'INVALID_ROUTE_INPUT',fields:p.error.issues.map(i=>({field:i.path.join('.'),message:i.message}))}); req.input=p.data;next();};
export function adminRouteRouter({repository,jeepneyRepository,config,clock}) {
  const router=Router();
  const body=[rateLimit({windowMs:60000,limit:60,keyGenerator:req=>req.admin.id,standardHeaders:'draft-8',legacyHeaders:false,message:{error:'ADMIN_WRITE_RATE_LIMITED'}}),(req,res,next)=>req.is('application/json')?next():res.status(415).json({error:'JSON_REQUIRED'}),json({limit:'16kb'})];
  router.get('/routes',validate(query,'query'),async(req,res)=>res.json({data:await repository.list(req.input)}));
  router.post('/routes',...body,validate(createRoute),async(req,res)=>{const id=await repository.create(req.input);res.status(201).json({data:await repository.get(id)});});
  router.use('/routes/:id',(req,res,next)=>z.uuid().safeParse(req.params.id).success?next():res.status(400).json({error:'INVALID_ID'}));
  router.get('/routes/:id',async(req,res)=>{const row=await repository.get(req.params.id);if(!row)return res.status(404).json({error:'ROUTE_NOT_FOUND'});res.json({data:row});});
  router.get('/routes/:id/jeepneys',validate(z.object(paging).strict(),'query'),async(req,res)=>{
    if(!await repository.get(req.params.id))return res.status(404).json({error:'ROUTE_NOT_FOUND'});
    res.json({data:await jeepneyRepository.list({...req.input,search:'',status:'all',routeId:req.params.id},clock(),config.STALE_AFTER_SECONDS)});
  });
  router.put('/routes/:id',...body,validate(edit),async(req,res)=>{await repository.update(req.params.id,req.input);res.json({data:await repository.get(req.params.id)});});
  router.post('/routes/:id/activation',...body,validate(activation),async(req,res)=>{await repository.update(req.params.id,req.input,true);res.json({data:await repository.get(req.params.id)});});
  router.use((e,req,res,next)=>{if(e.code==='23505')return res.status(409).json({error:'ROUTE_EXISTS'});if(e.message==='RECORD_CHANGED')return res.status(409).json({error:e.message});if(e.message==='ROUTE_NOT_FOUND')return res.status(404).json({error:e.message});next(e);});
  return router;
}

import type { Env } from './types';
import { Router, withAuth } from './lib/router';
import { bootstrap } from './routes/auth';
import { getCity } from './routes/city';
import { placeModule, removeModule } from './routes/modules';
import { collectProduction, claimOfflineRewards } from './routes/production';
import { listContracts, acceptContract, submitContract } from './routes/contracts';
import { listWorldEvents } from './routes/worldEvents';
import { getWorldProject, contributeToProject } from './routes/worldProject';
import { listBlueprints, getBlueprint, saveBlueprint } from './routes/blueprints';
import { json } from './lib/response';

export { WorldProjectRoom } from './durable/WorldProjectRoom';

const router = new Router();

// -- auth --------------------------------------------------------------
router.post('/api/v1/auth/bootstrap', bootstrap);

// -- city ----------------------------------------------------------------
router.get('/api/v1/city', withAuth(getCity));

// -- modules ---------------------------------------------------------------
router.post('/api/v1/modules/place', withAuth(placeModule));
router.post('/api/v1/modules/remove', withAuth(removeModule));

// -- production --------------------------------------------------------------
router.post('/api/v1/production/collect', withAuth(collectProduction));
router.post('/api/v1/production/claim-offline', withAuth(claimOfflineRewards));

// -- contracts --------------------------------------------------------------
router.get('/api/v1/contracts', withAuth(listContracts));
router.post('/api/v1/contracts/:contractId/accept', withAuth(acceptContract));
router.post('/api/v1/contracts/:playerContractId/submit', withAuth(submitContract));

// -- world events --------------------------------------------------------------
router.get('/api/v1/world-events', withAuth(listWorldEvents));

// -- world project (Durable Object-backed) --------------------------------------------------------------
router.get('/api/v1/world-project', withAuth(getWorldProject));
router.post('/api/v1/world-project/contribute', withAuth(contributeToProject));

// -- blueprints --------------------------------------------------------------
router.get('/api/v1/blueprints', withAuth(listBlueprints));
router.get('/api/v1/blueprints/:id', withAuth(getBlueprint));
router.post('/api/v1/blueprints', withAuth(saveBlueprint));

// -- misc --------------------------------------------------------------
router.get('/api/v1/health', async () => json({ ok: true }));

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return router.handle(request, env);
  },
};

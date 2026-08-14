import { describe, expect, it } from 'vitest'
import accessFunction from '../../supabase/functions/chemistry-access/index.ts?raw'
import teacherFunction from '../../supabase/functions/chemistry-teacher/index.ts?raw'
import migration from '../../supabase/migrations/20260814125557_add_private_video_recommendations.sql?raw'

describe('private video recommendation backend contract', () => {
  it('keeps all video tables in the private schema with no direct client or service-role table grants', () => {
    expect(migration).toContain('app_private.chem_video_recommendations')
    expect(migration).toContain('app_private.chem_video_engagements')
    expect(migration).toContain('app_private.chem_video_engagement_events')
    expect(migration).toMatch(/enable row level security/g)
    expect(migration).toMatch(/revoke all on table app_private\.chem_video_recommendations from public, anon, authenticated, service_role/)
    expect(migration).toMatch(/grant execute on function public\.chem_video_list_recommendations[\s\S]*to service_role/)
  })

  it('requires teacher publication before student or guardian reads and before engagement writes', () => {
    expect(migration).toContain("and (p_include_unpublished or r.status = 'published')")
    expect(migration).toContain("and status = 'published';")
    expect(teacherFunction).toContain('publish_video_recommendation')
    expect(accessFunction).toContain('identity.role === "student"')
  })

  it('preserves honest provenance for link opens, self reports, and player events', () => {
    expect(migration).toContain("tracking_method in ('link_open_only','self_reported','player_tracked')")
    expect(migration).toContain("p_event_type = 'open'")
    expect(migration).toContain("v_method := 'link_open_only'")
    expect(migration).toContain("p_tracking_method <> v_capability")
    expect(accessFunction).toContain('record_video_engagement')
  })
})

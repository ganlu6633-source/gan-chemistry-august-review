import { describe, expect, it } from 'vitest'
import recoveryMigration from '../../supabase/migrations/20260830233000_recover_unanswered_blocked_junior_sessions.sql?raw'

describe('junior unanswered blocked-session recovery migration', () => {
  it('takes the canonical release locks before any session row lock', () => {
    const sourceLock = recoveryMigration.indexOf("hashtextextended('chem-source-original-release', 0)")
    const legacyLock = recoveryMigration.indexOf("hashtextextended('chem-h3-original-release', 0)")
    const sessionLock = recoveryMigration.indexOf('for update;')
    expect(sourceLock).toBeGreaterThan(-1)
    expect(sourceLock).toBeLessThan(legacyLock)
    expect(legacyLock).toBeLessThan(sessionLock)
  })

  it('requires one active verified native 科粤版 release and ready knowledge cards', () => {
    expect(recoveryMigration).toContain("release_row.grade_band = '初三'")
    expect(recoveryMigration).toContain("release_row.textbook_version = '科粤版'")
    expect(recoveryMigration).toContain("release_row.status = 'active'")
    expect(recoveryMigration).toContain("release_row.verification_status = 'full_visual_verified'")
    expect(recoveryMigration).toContain("release_row.revision_contract = 'v3_junior_native_text'")
    expect(recoveryMigration).toContain('app_private.chem_junior_knowledge_card_is_ready(')
  })

  it('selects only source-release blocks that have no answered evidence', () => {
    expect(recoveryMigration).toContain("session_row.status = 'blocked'")
    expect(recoveryMigration).toContain("session_row.blocked_reason_code = 'source_release_unavailable'")
    expect(recoveryMigration).toMatch(/not exists \([\s\S]*answered_step\.answered_at is not null/)
    expect(recoveryMigration).not.toContain("blocked_reason_code = 'manual_pause'")
  })

  it('deletes only unanswered stale steps and never a session or answer', () => {
    expect(recoveryMigration).toMatch(/delete from public\.chem_junior_session_steps[\s\S]*stale_step\.answered_at is null/)
    expect(recoveryMigration).not.toMatch(/delete from public\.chem_junior_daily_sessions/)
    expect(recoveryMigration).not.toMatch(/update public\.chem_junior_session_steps/)
  })

  it('clears blocked metadata while returning the same session to active', () => {
    expect(recoveryMigration).toContain("set status = 'active'")
    expect(recoveryMigration).toContain('blocked_reason_code = null')
    expect(recoveryMigration).toContain('blocked_reason_detail = null')
    expect(recoveryMigration).toContain('blocked_at = null')
  })
})

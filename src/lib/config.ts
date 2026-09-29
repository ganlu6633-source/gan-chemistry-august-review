export const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL || 'https://phdleezffrqqzyveicrm.supabase.co'
export const SUPABASE_PUBLISHABLE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || 'sb_publishable_M4xdf_9aRaxoEnHnTQZ_rg_uIQfeEgb'
export const ACCESS_FUNCTION = import.meta.env.VITE_ACCESS_FUNCTION || 'chemistry-access'
export const TEACHER_FUNCTION = import.meta.env.VITE_TEACHER_FUNCTION || 'chemistry-teacher'
// Use "any" to restore automatic routing without changing the four junior actions.
export const JUNIOR_FUNCTION_REGION = (import.meta.env.VITE_JUNIOR_FUNCTION_REGION ?? 'ap-southeast-2').trim()
export const APP_TIME_ZONE = 'Asia/Shanghai'

export function functionUrl(slug: string) {
  return `${SUPABASE_URL}/functions/v1/${slug}`
}

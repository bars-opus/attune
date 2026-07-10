// supabase/functions/send-checkin-reminders/index.ts

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const weekEnding = _getWeekEnding(new Date())
    const weekEndingStr = weekEnding.toISOString().split('T')[0]

    // Get all active relationships
    const { data: relationships } = await supabase
      .from('relationships')
      .select('id, user_a, user_b')
      .eq('status', 'active')

    if (!relationships) {
      return new Response(JSON.stringify({ message: 'No active relationships' }), { headers: corsHeaders })
    }

    const remindersSent = []

    for (const relationship of relationships) {
      // Check which users haven't completed check-in this week
      const { data: existingCheckins } = await supabase
        .from('weekly_checkins')
        .select('user_id')
        .eq('relationship_id', relationship.id)
        .eq('week_ending', weekEndingStr)

      const completedUserIds = existingCheckins?.map(c => c.user_id) || []
      const allUserIds = [relationship.user_a, relationship.user_b]
      const pendingUserIds = allUserIds.filter(id => !completedUserIds.includes(id))

      // Get partner names for pending users
      for (const userId of pendingUserIds) {
        const { data: profile } = await supabase
          .from('profiles')
          .select('display_name')
          .eq('id', userId)
          .single()

        const partnerId = userId === relationship.user_a ? relationship.user_b : relationship.user_a
        const { data: partnerProfile } = await supabase
          .from('profiles')
          .select('display_name')
          .eq('id', partnerId)
          .single()

        remindersSent.push({
          user_id: userId,
          partner_name: partnerProfile?.display_name || 'Partner',
        })
      }
    }

    // Call notification service edge function
    for (const reminder of remindersSent) {
      await supabase.functions.invoke('send-notification', {
        body: {
          userId: reminder.user_id,
          type: 'checkin_reminder',
          partnerName: reminder.partner_name,
        },
      })
    }

    return new Response(
      JSON.stringify({ success: true, remindersSent: remindersSent.length }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Error:', error.message)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

function _getWeekEnding(date: Date): Date {
  const result = new Date(date)
  const daysToSunday = 7 - result.getDay()
  result.setDate(result.getDate() + daysToSunday)
  result.setHours(0, 0, 0, 0)
  return result
}
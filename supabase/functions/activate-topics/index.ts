// supabase/functions/activate-topics/index.ts

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

Deno.serve(async (req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  console.log('Running topic activation check...');

  // Find topics in voting phase that have enough seen_count
  const { data: topics, error } = await supabase
    .from('forum_topics')
    .select('*')
    .eq('status', 'voting')
    .gte('seen_count', 20)
    .lt('voting_expires_at', new Date().toISOString());

  if (error) {
    console.error('Error fetching topics:', error);
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }

  const activatedTopics = [];

  for (const topic of topics) {
    const activationPercentage = topic.upvote_count / topic.seen_count;
    
    if (activationPercentage > 0.5) {
      // Activate this topic
      const { error: updateError } = await supabase
        .from('forum_topics')
        .update({
          status: 'active',
          activated_at: new Date().toISOString(),
        })
        .eq('id', topic.id);

      if (updateError) {
        console.error(`Error activating topic ${topic.id}:`, updateError);
        continue;
      }

      activatedTopics.push(topic);

      // Get all users who voted on this topic
      const { data: votes, error: votesError } = await supabase
        .from('topic_votes')
        .select('user_id, vote_type')
        .eq('topic_id', topic.id);

      if (votesError) {
        console.error(`Error fetching votes for topic ${topic.id}:`, votesError);
        continue;
      }

      // Send notifications via OneSignal
      const forUsers = votes.filter(v => v.vote_type === 'up').map(v => v.user_id);
      const againstUsers = votes.filter(v => v.vote_type === 'down').map(v => v.user_id);

      // In production, call OneSignal API here
      console.log(`Topic activated: ${topic.content}`);
      console.log(`FOR users: ${forUsers.length}, AGAINST users: ${againstUsers.length}`);
    }
  }

  // Handle expired topics
  const { data: expiredTopics, error: expiredError } = await supabase
    .from('forum_topics')
    .select('id')
    .eq('status', 'voting')
    .lt('voting_expires_at', new Date().toISOString());

  if (!expiredError && expiredTopics && expiredTopics.length > 0) {
    const expiredIds = expiredTopics.map(t => t.id);
    await supabase
      .from('forum_topics')
      .update({ status: 'expired' })
      .in('id', expiredIds);
    console.log(`Expired ${expiredIds.length} topics`);
  }

  return new Response(
    JSON.stringify({
      activated: activatedTopics.length,
      activatedTopics: activatedTopics.map(t => t.content),
    }),
    { status: 200 }
  );
});
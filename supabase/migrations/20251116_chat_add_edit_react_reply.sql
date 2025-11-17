-- Migration: adicionar suporte a respostas (parent_id), edição (edited_at) e reações (message_reactions)
-- Pré-requisitos: tabelas públicas 'messages', 'rooms', 'room_members' já existentes e RLS configurado nelas.
-- Ajuste os nomes de esquema/tabelas se sua estrutura diferir.

-- 1) Replies e edição em messages
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'messages'
      AND column_name = 'parent_id'
  ) THEN
    ALTER TABLE public.messages
      ADD COLUMN parent_id uuid NULL REFERENCES public.messages(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'messages'
      AND column_name = 'edited_at'
  ) THEN
    ALTER TABLE public.messages
      ADD COLUMN edited_at timestamptz NULL;
  END IF;
END $$;

-- 2) Tabela de reações
CREATE TABLE IF NOT EXISTS public.message_reactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  room_id uuid NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  emoji text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (message_id, user_id, emoji)
);

-- Índices úteis
CREATE INDEX IF NOT EXISTS idx_message_reactions_room_message ON public.message_reactions (room_id, message_id);
CREATE INDEX IF NOT EXISTS idx_message_reactions_message_emoji ON public.message_reactions (message_id, emoji);
CREATE INDEX IF NOT EXISTS idx_message_reactions_user ON public.message_reactions (user_id);

-- 3) RLS para reactions
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

-- Permitir SELECT a membros da sala
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'message_reactions' AND policyname = 'Select reactions for room members'
  ) THEN
    CREATE POLICY "Select reactions for room members"
      ON public.message_reactions
      FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM public.room_members rm
          WHERE rm.room_id = message_reactions.room_id
            AND rm.user_id = auth.uid()
        )
      );
  END IF;
END $$;

-- Permitir INSERT ao próprio usuário
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'message_reactions' AND policyname = 'Insert own reactions'
  ) THEN
    CREATE POLICY "Insert own reactions"
      ON public.message_reactions
      FOR INSERT
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- Permitir DELETE do próprio usuário
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'message_reactions' AND policyname = 'Delete own reactions'
  ) THEN
    CREATE POLICY "Delete own reactions"
      ON public.message_reactions
      FOR DELETE
      USING (user_id = auth.uid());
  END IF;
END $$;

-- 4) (Opcional) Política para permitir UPDATE de messages somente pelo autor
-- Ajuste se já houver políticas cobrindo esse caso
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'messages' AND policyname = 'Update own messages content'
  ) THEN
    CREATE POLICY "Update own messages content"
      ON public.messages
      FOR UPDATE
      USING (from_id = auth.uid())
      WITH CHECK (from_id = auth.uid());
  END IF;
END $$;

-- Observação:
-- A aplicação definirá edited_at ao atualizar a mensagem.
-- parent_id é livre (nullable); quando presente, o front exibirá o contexto da resposta.




-- ═══════════════════════════════════════════════
--  KLAR FOR KUNDE — Database Schema
-- ═══════════════════════════════════════════════

-- Regions
CREATE TABLE public.regions (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name text NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Stations (273 YX stasjoner)
CREATE TABLE public.stations (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name text NOT NULL,
  address text,
  postnr text,
  poststed text,
  lat float,
  lng float,
  type text CHECK (type IN ('fullservice', 'automat')),
  forhandler text,
  mobil text,
  selskap text,
  region_id uuid REFERENCES public.regions(id),
  created_at timestamptz DEFAULT now()
);

-- Profiles (extends Supabase Auth)
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name text,
  role text CHECK (role IN ('stasjonsleder', 'regionssjef', 'leder')) NOT NULL DEFAULT 'stasjonsleder',
  station_id uuid REFERENCES public.stations(id),
  region_id uuid REFERENCES public.regions(id),
  created_at timestamptz DEFAULT now()
);

-- Visits
CREATE TABLE public.visits (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  station_id uuid NOT NULL REFERENCES public.stations(id),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  visit_role text CHECK (visit_role IN ('sl', 'rs')) NOT NULL,
  scores jsonb DEFAULT '{}',
  na_items jsonb DEFAULT '[]',
  notes jsonb DEFAULT '{}',
  visit_note text,
  total_score int DEFAULT 0,
  max_score int DEFAULT 0,
  pct int DEFAULT 0,
  photo_count int DEFAULT 0,
  status text CHECK (status IN ('draft', 'completed')) DEFAULT 'completed',
  created_at timestamptz DEFAULT now()
);

-- Visit photos
CREATE TABLE public.visit_photos (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  visit_id uuid NOT NULL REFERENCES public.visits(id) ON DELETE CASCADE,
  item_id int,
  storage_path text NOT NULL,
  lat float,
  lng float,
  created_at timestamptz DEFAULT now()
);

-- Actions (tiltak/avvik)
CREATE TABLE public.actions (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  visit_id uuid REFERENCES public.visits(id),
  station_id uuid NOT NULL REFERENCES public.stations(id),
  item_id int,
  description text NOT NULL,
  assigned_to text CHECK (assigned_to IN ('stasjon', 'regionssjef', 'drift')) DEFAULT 'stasjon',
  due_date date,
  priority text CHECK (priority IN ('low', 'medium', 'high')) DEFAULT 'medium',
  status text CHECK (status IN ('open', 'in_progress', 'completed', 'overdue')) DEFAULT 'open',
  completed_at timestamptz,
  completed_by uuid REFERENCES auth.users(id),
  evidence_photo text,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now()
);

-- HMS checks
CREATE TABLE public.hms_checks (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  station_id uuid NOT NULL REFERENCES public.stations(id),
  tertial text CHECK (tertial IN ('t1', 't2', 't3')) NOT NULL,
  item_id text NOT NULL,
  year int NOT NULL DEFAULT EXTRACT(YEAR FROM now()),
  checked boolean DEFAULT false,
  checked_by uuid REFERENCES auth.users(id),
  checked_at timestamptz,
  UNIQUE(station_id, tertial, item_id, year)
);

-- Campaign data
CREATE TABLE public.campaigns (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  period text NOT NULL,
  name text NOT NULL,
  start_week int,
  end_week int,
  items jsonb NOT NULL DEFAULT '[]',
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

-- ═══════════════════════════════════════════════
--  ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════

ALTER TABLE public.regions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visit_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hms_checks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.campaigns ENABLE ROW LEVEL SECURITY;

-- Regions: all authenticated users can read
CREATE POLICY "regions_read" ON public.regions FOR SELECT TO authenticated USING (true);

-- Stations: stasjonsleder sees own, RS sees region, leder sees all
CREATE POLICY "stations_read" ON public.stations FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND (
      p.role = 'leder' OR
      (p.role = 'stasjonsleder' AND p.station_id = stations.id) OR
      (p.role = 'regionssjef' AND p.region_id = stations.region_id)
    )
  )
);

-- Profiles: users can read own + same region/station
CREATE POLICY "profiles_read_own" ON public.profiles FOR SELECT TO authenticated USING (id = auth.uid());
CREATE POLICY "profiles_update_own" ON public.profiles FOR UPDATE TO authenticated USING (id = auth.uid());

-- Visits: creator + station/region members can read
CREATE POLICY "visits_insert" ON public.visits FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "visits_read" ON public.visits FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND (
      p.role = 'leder' OR
      visits.user_id = auth.uid() OR
      (p.role = 'stasjonsleder' AND p.station_id = visits.station_id) OR
      (p.role = 'regionssjef' AND EXISTS (
        SELECT 1 FROM public.stations s WHERE s.id = visits.station_id AND s.region_id = p.region_id
      ))
    )
  )
);

-- Actions: similar to visits
CREATE POLICY "actions_insert" ON public.actions FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid());
CREATE POLICY "actions_read" ON public.actions FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND (
      p.role = 'leder' OR
      (p.role = 'stasjonsleder' AND p.station_id = actions.station_id) OR
      (p.role = 'regionssjef' AND EXISTS (
        SELECT 1 FROM public.stations s WHERE s.id = actions.station_id AND s.region_id = p.region_id
      ))
    )
  )
);
CREATE POLICY "actions_update" ON public.actions FOR UPDATE TO authenticated USING (
  EXISTS (
    SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND (
      p.role = 'leder' OR
      actions.created_by = auth.uid() OR
      (p.role = 'stasjonsleder' AND p.station_id = actions.station_id)
    )
  )
);

-- HMS checks: station + region can read/write
CREATE POLICY "hms_read" ON public.hms_checks FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND (
      p.role = 'leder' OR
      (p.role = 'stasjonsleder' AND p.station_id = hms_checks.station_id) OR
      (p.role = 'regionssjef' AND EXISTS (
        SELECT 1 FROM public.stations s WHERE s.id = hms_checks.station_id AND s.region_id = p.region_id
      ))
    )
  )
);
CREATE POLICY "hms_upsert" ON public.hms_checks FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "hms_update" ON public.hms_checks FOR UPDATE TO authenticated USING (true);

-- Visit photos: same as visits
CREATE POLICY "photos_insert" ON public.visit_photos FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "photos_read" ON public.visit_photos FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.visits v WHERE v.id = visit_photos.visit_id)
);

-- Campaigns: all authenticated can read
CREATE POLICY "campaigns_read" ON public.campaigns FOR SELECT TO authenticated USING (true);

-- ═══════════════════════════════════════════════
--  AUTO-CREATE PROFILE ON SIGNUP
-- ═══════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, name, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', NEW.email),
    COALESCE(NEW.raw_user_meta_data->>'role', 'stasjonsleder')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


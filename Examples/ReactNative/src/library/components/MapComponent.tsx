import { createContext, useContext, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { ActivityIndicator, FlatList, Modal, Pressable, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Map as NativeMap, Camera, Marker, type CameraRef } from '@maplibre/maplibre-react-native';
import { BuiltinActionType, useIsStreaming, type ComponentRenderer } from '@openuidev/react-lang';
import { useDocumentInteraction } from '../../runtime/interaction';
import { useOpenUITheme } from '../theme';
import { NativeImage } from './NativeImage';
import { NativeIcon } from './NativeIcon';
import { contentLink, useNativeContentPolicy } from './contentPolicy';
import { useNativeAction } from './useNativeAction';
import { mapBounds, mapPlaces, type MapPlace } from './mapData';

// Development tiles are the MapLibre project's documented default. A production
// host supplies its own licensed style/tiles without changing the Lang contract.
const MapStyle = createContext('https://demotiles.maplibre.org/style.json');
export function NativeMapProvider({ children, mapStyle }: { children: ReactNode; mapStyle: string }) {
  const url = contentLink(mapStyle);
  if (!url?.startsWith('https:')) throw new Error('Map style must be a valid HTTPS URL');
  return <MapStyle.Provider value={url}>{children}</MapStyle.Provider>;
}

function MapControl({ label, icon, onPress, disabled = false }: {
  label: string; icon: string; onPress: () => void; disabled?: boolean;
}) {
  const theme = useOpenUITheme();
  return <Pressable accessibilityRole="button" accessibilityLabel={label} accessibilityState={{ disabled }}
    disabled={disabled} onPress={onPress} style={({ pressed }) => ({ width: theme.controlMinHeight,
      height: theme.controlMinHeight, borderRadius: 12, backgroundColor: theme.surface,
      justifyContent: 'center', alignItems: 'center', opacity: disabled ? 0.5 : pressed ? 0.7 : 1 })}>
    <NativeIcon name={icon} size={20} color={theme.accent} />
  </Pressable>;
}

function MapSurface({ places, selected, select, expand, fullscreen, close, mapStyle }: {
  places: MapPlace[]; selected?: MapPlace; select: (id: string) => void; expand: () => void;
  fullscreen: boolean; close: () => void; mapStyle: string;
}) {
  const theme = useOpenUITheme();
  const { canInteract } = useDocumentInteraction();
  const streaming = useIsStreaming();
  const { onError } = useNativeContentPolicy();
  const camera = useRef<CameraRef>(null);
  const mounted = useRef(true);
  const [failed, setFailed] = useState(false);
  const [loadedRequest, setLoadedRequest] = useState<object>();
  const [attempt, setAttempt] = useState(0);
  const [query, setQuery] = useState('');
  const filtered = useMemo(() => places.filter(place => place.title.toLocaleLowerCase().includes(query.toLocaleLowerCase())),
    [places, query]);
  const tooMany = filtered.length > 512;
  const enabled = !streaming && canInteract();
  const canLoad = enabled && !tooMany && filtered.length > 0;
  const rendersMap = canLoad && !failed;
  // Filtering to zero points really unmounts the native view, even without a
  // retry. Events from that retired view must not affect a later mount.
  const request = useMemo(() => ({ retired: false }), [mapStyle, attempt, rendersMap]);
  const loaded = loadedRequest === request;
  const current = useRef({ filtered, streaming, canInteract, request, failed, select, onError });
  const active = () => mounted.current && !current.current.streaming && current.current.canInteract();
  const ownsRequest = () => active() && current.current.request === request && !request.retired;
  useLayoutEffect(() => {
    mounted.current = true;
    return () => { mounted.current = false; };
  }, []);
  useLayoutEffect(() => {
    current.current = { filtered, streaming, canInteract, request, failed, select, onError };
  }, [filtered, streaming, canInteract, request, failed, select, onError]);
  const fit = () => {
    if (!ownsRequest()) return;
    // A native completion may have been enqueued before a same-view point or
    // query update. Fit the latest committed data, not its old JS closure.
    const points = current.current.filtered;
    const bounds = mapBounds(points);
    if (points.length === 1) camera.current?.easeTo({ center: [points[0].lng, points[0].lat], zoom: 13, duration: 200 });
    else if (bounds) camera.current?.fitBounds(bounds, { padding: { top: 56, bottom: 56, left: 40, right: 40 }, duration: 200 });
  };
  const pick = (place: MapPlace) => {
    if (!ownsRequest()) return;
    const point = current.current.filtered.find(value => value.id === place.id);
    if (!point) return;
    current.current.select(point.id);
    if (ownsRequest()) camera.current?.easeTo({ center: [point.lng, point.lat], zoom: 14, duration: 200 });
  };
  const initial = mapBounds(filtered);
  return <View style={{ flex: fullscreen ? 1 : undefined, gap: 10, minWidth: 0 }}>
    <View style={{ flex: fullscreen ? 1 : undefined, height: fullscreen ? undefined : 320,
      minHeight: 240, borderRadius: 16, overflow: 'hidden', backgroundColor: theme.surfaceMuted }}>
      {rendersMap ? <NativeMap key={`${mapStyle}:${attempt}`} mapStyle={mapStyle}
        testID="openui-native-map" style={{ flex: 1 }} attribution logo compass
        dragPan={!streaming} touchZoom={!streaming} touchRotate={!streaming} touchPitch={false}
        tintColor={theme.accent} onDidFinishLoadingMap={() => {
          if (ownsRequest()) { setLoadedRequest(request); fit(); }
        }} onDidFailLoadingMap={() => {
          if (!ownsRequest()) return;
          // Retire synchronously, including duplicate native errors in the same
          // React batch before the failed placeholder has committed.
          request.retired = true;
          setFailed(true); setLoadedRequest(undefined);
          try { current.current.onError?.(new Error('Map tiles failed to load')); } catch { /* Reporting cannot retire content. */ }
        }}>
        <Camera ref={camera} initialViewState={filtered.length === 1
          ? { center: [filtered[0].lng, filtered[0].lat], zoom: 13 }
          : initial ? { bounds: initial, padding: { top: 56, bottom: 56, left: 40, right: 40 } } : undefined} />
        {filtered.map((place, index) => <Marker key={place.id} id={place.id} lngLat={[place.lng, place.lat]}
          onPress={() => pick(place)}>
          <View accessible accessibilityRole="button" accessibilityLabel={`选择${place.title}`}
            accessibilityState={{ selected: place.id === selected?.id }}
            style={{ width: 34, height: 34, borderRadius: 17, borderWidth: 2, borderColor: theme.surface,
              backgroundColor: place.id === selected?.id ? theme.accent : theme.ink, alignItems: 'center', justifyContent: 'center' }}>
            <Text style={{ color: theme.surface, fontSize: 13, fontWeight: '600' }}>{index + 1}</Text>
          </View>
        </Marker>)}
      </NativeMap> : <Pressable accessibilityRole={failed ? 'button' : 'image'}
        accessibilityLabel={failed ? '重新加载地图' : streaming ? '地图正在生成' : tooMany ? '地点超过地图绘制上限，请筛选' : '没有可显示的地点'}
        disabled={!failed} onPress={() => {
          if (!ownsRequest() || !current.current.failed) return;
          request.retired = true;
          setFailed(false); setLoadedRequest(undefined); setAttempt(value => value + 1);
        }} style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
        <NativeIcon name="map" size={28} color={theme.muted} />
        {tooMany ? <Text style={{ color: theme.muted, marginTop: 8 }}>地点较多，请先筛选</Text> : null}
      </Pressable>}
      {canLoad && !loaded && !failed ? <View pointerEvents="none" style={{ position: 'absolute', top: 16, left: 16 }}>
        <ActivityIndicator color={theme.accent} accessibilityLabel="正在加载地图" />
      </View> : null}
      <View style={{ position: 'absolute', top: 12, right: 12, gap: 8 }}>
        <MapControl label="显示全部地点" icon="scan" disabled={!canLoad || failed} onPress={fit} />
        <MapControl label={fullscreen ? '收起地图' : '展开地图'} icon={fullscreen ? 'minimize-2' : 'maximize-2'}
          disabled={!enabled} onPress={() => { if (active()) fullscreen ? close() : expand(); }} />
      </View>
    </View>
    {places.length > 5 ? <TextInput accessibilityLabel="筛选地点" placeholder="搜索地点" value={query}
      editable={!streaming && canInteract()} onChangeText={value => { if (active()) setQuery(value); }}
      placeholderTextColor={theme.muted} style={{ minHeight: 48, paddingHorizontal: 12, color: theme.ink,
        backgroundColor: theme.surface, borderWidth: 1, borderColor: theme.border, borderRadius: 12 }} /> : null}
    {places.length > 1 ? <FlatList horizontal data={filtered} keyExtractor={place => place.id}
      keyboardShouldPersistTaps="handled" showsHorizontalScrollIndicator={false}
      contentContainerStyle={{ gap: 8 }} style={{ flexGrow: 0 }} initialNumToRender={6} maxToRenderPerBatch={6}
      renderItem={({ item }) => <Pressable accessibilityRole="button" accessibilityLabel={`选择${item.title}`}
        disabled={!enabled} accessibilityState={{ selected: item.id === selected?.id, disabled: !enabled }}
        onPress={() => pick(item)} style={({ pressed }) => ({ minHeight: 48, paddingHorizontal: 14, paddingVertical: 10,
          justifyContent: 'center', borderRadius: 12, borderWidth: 1,
          borderColor: item.id === selected?.id ? theme.accent : theme.border,
          backgroundColor: theme.surface, opacity: pressed ? 0.7 : 1 })}>
        <Text style={{ color: item.id === selected?.id ? theme.accent : theme.ink, fontSize: 14 }}>{item.title}</Text>
      </Pressable>} /> : null}
    {selected ? <PlaceCard place={selected} /> : null}
  </View>;
}

function PlaceCard({ place }: { place: MapPlace }) {
  const theme = useOpenUITheme();
  const url = place.url ? contentLink(place.url) : undefined;
  const { invoke, canInvoke, disabled } = useNativeAction(JSON.stringify([place.id, url]));
  return <View style={{ flexDirection: 'row', gap: 12, minWidth: 0, padding: 12,
    borderRadius: 12, backgroundColor: theme.surface }}>
    {place.image ? <View style={{ width: 76 }}><NativeImage source={place.image} alt={place.title} compact aspectRatio={1} /></View> : null}
    <View style={{ flex: 1, gap: 4 }}>
      <Text accessibilityRole="header" style={{ color: theme.ink, fontSize: 16, fontWeight: '600', lineHeight: 24 }}>{place.title}</Text>
      {place.description ? <Text selectable style={{ color: theme.muted, fontSize: 13, lineHeight: 20 }}>{place.description}</Text> : null}
      {url ? <Pressable accessibilityRole="link" accessibilityLabel={`查看${place.title}`} disabled={disabled}
        onPress={() => { if (canInvoke()) void invoke(place.title, { type: BuiltinActionType.OpenUrl, params: { url } }); }}
        style={{ minHeight: 48, justifyContent: 'center', alignSelf: 'flex-start' }}>
        <Text style={{ color: theme.accent, fontSize: 14 }}>查看详情</Text>
      </Pressable> : null}
    </View>
  </View>;
}

const MapComponent: ComponentRenderer = ({ props }) => {
  const theme = useOpenUITheme();
  const mapStyle = useContext(MapStyle);
  const places = useMemo(() => mapPlaces(props.points, typeof props.crs === 'string' ? props.crs : 'wgs84'), [props.points, props.crs]);
  const [selectedId, setSelectedId] = useState<string>();
  const [expanded, setExpanded] = useState(false);
  const { canInteract } = useDocumentInteraction();
  const mounted = useRef(true);
  useLayoutEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  const selected = places.find(place => place.id === selectedId) ?? places[0];
  const close = () => { if (mounted.current && canInteract()) setExpanded(false); };
  const surface = (fullscreen: boolean) => <MapSurface key={`${mapStyle}:${fullscreen}`} places={places} selected={selected}
    select={id => { if (mounted.current && canInteract()) setSelectedId(id); }}
    expand={() => { if (mounted.current && canInteract()) setExpanded(true); }} close={close}
    fullscreen={fullscreen} mapStyle={mapStyle} />;
  return <View style={{ minWidth: 0 }}>
    {!expanded ? surface(false) : <View style={{ height: 320, borderRadius: 16, backgroundColor: theme.surfaceMuted }} />}
    <Modal visible={expanded} animationType="slide" onRequestClose={close} accessibilityViewIsModal>
      {expanded ? <SafeAreaView style={{ flex: 1, padding: 16, backgroundColor: theme.background }}>{surface(true)}</SafeAreaView> : null}
    </Modal>
  </View>;
};

export const mapRenderers: Record<string, ComponentRenderer> = { Map: MapComponent, MapPoint: () => null };

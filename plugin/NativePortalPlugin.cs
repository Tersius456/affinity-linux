using System;
using System.IO;
using System.Diagnostics;
using System.Reflection;
using System.Threading;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls.Primitives;
using System.Windows.Threading;
using HarmonyLib;
using Microsoft.Win32;
using AffinityPluginLoader;
using AffinityPluginLoader.Core;

namespace NativePortal
{
    public class NativePortalPlugin : AffinityPlugin
    {
        public const string PluginId = "native_portal";
        private static bool _initialized = false;
        private static bool _queueWatcherStarted = false;
        private static string QUEUE_FILE = @"Z:\tmp\affinity_open_queue.txt";
        private static readonly List<WeakReference> _openPopups = new List<WeakReference>();

        public override void OnPatch(Harmony harmony, IPluginContext context)
        {
            Logger.Info("[NativePortal] Initializing NativePortal plugin...");
            try
            {
                var runDialog = typeof(FileDialog).GetMethod("RunDialog", BindingFlags.NonPublic | BindingFlags.Instance);
                if (runDialog != null)
                {
                    var prefix = typeof(NativePortalPlugin).GetMethod("RunDialog_Prefix", BindingFlags.Static | BindingFlags.Public);
                    harmony.Patch(runDialog, prefix: new HarmonyMethod(prefix));
                    Logger.Info("[NativePortal] Hooked FileDialog.RunDialog!");
                }
            }
            catch (Exception ex) { Logger.Error("[NativePortal] FileDialog hook error: " + ex.Message); }

            // SubToolPanel / PinnableWindow hooks: Anchor subtools properly to toolbar and prevent desktop floating
            try
            {
                var subToolType = AccessTools.TypeByName("Serif.Affinity.UI.Controls.Tools.SubToolPanel");
                if (subToolType != null)
                {
                    var setPos = AccessTools.Method(subToolType, "SetPosition", new Type[] { typeof(FrameworkElement) });
                    if (setPos != null)
                    {
                        var prefix = typeof(NativePortalPlugin).GetMethod("SubToolPanel_SetPosition_Prefix", BindingFlags.Static | BindingFlags.Public);
                        harmony.Patch(setPos, prefix: new HarmonyMethod(prefix));
                        Logger.Info("[NativePortal] Hooked SubToolPanel.SetPosition!");
                    }
                }

                var pinWinType = AccessTools.TypeByName("Serif.Affinity.UI.Pinning.PinnableWindow");
                if (pinWinType != null)
                {
                    var restorePos = AccessTools.Method(pinWinType, "RestoreLastPosition");
                    if (restorePos != null)
                    {
                        var prefix = typeof(NativePortalPlugin).GetMethod("PinnableWindow_RestoreLastPosition_Prefix", BindingFlags.Static | BindingFlags.Public);
                        harmony.Patch(restorePos, prefix: new HarmonyMethod(prefix));
                        Logger.Info("[NativePortal] Hooked PinnableWindow.RestoreLastPosition!");
                    }
                }
            }
            catch (Exception ex) { Logger.Error("[NativePortal] SubToolPanel hooks error: " + ex.Message); }

            // Hook Popup for tracking and clean dismissal
            try
            {
                var onOpened = typeof(Popup).GetMethod("OnOpened", BindingFlags.NonPublic | BindingFlags.Instance);
                if (onOpened != null)
                {
                    var postfix = typeof(NativePortalPlugin).GetMethod("Popup_OnOpened_Postfix", BindingFlags.Static | BindingFlags.Public);
                    harmony.Patch(onOpened, postfix: new HarmonyMethod(postfix));
                    Logger.Info("[NativePortal] Hooked Popup.OnOpened!");
                }

                var onClosed = typeof(Popup).GetMethod("OnClosed", BindingFlags.NonPublic | BindingFlags.Instance);
                if (onClosed != null)
                {
                    var postfix = typeof(NativePortalPlugin).GetMethod("Popup_OnClosed_Postfix", BindingFlags.Static | BindingFlags.Public);
                    harmony.Patch(onClosed, postfix: new HarmonyMethod(postfix));
                    Logger.Info("[NativePortal] Hooked Popup.OnClosed!");
                }
            }
            catch (Exception ex) { Logger.Error("[NativePortal] Popup hooks error: " + ex.Message); }
        }

        public static bool SubToolPanel_SetPosition_Prefix(object __instance, FrameworkElement host)
        {
            if (__instance == null || host == null) return true;
            try
            {
                var win = __instance as Window;
                if (win == null || !host.IsVisible) return true;

                // host is the ToolHost or ToolTrayButton on the left toolbar.
                // Calculate device screen coordinates right next to the button.
                Point screenPt = host.PointToScreen(new Point(host.ActualWidth + 2, 0));

                if (screenPt.X >= 0 && screenPt.Y >= 0)
                {
                    var dpiType = AccessTools.TypeByName("Serif.Windows.UI.Win32Dpi");
                    if (dpiType != null)
                    {
                        var setDevicePos = AccessTools.Method(dpiType, "SetDevicePosition", new Type[] { typeof(Window), typeof(double), typeof(double), typeof(double), typeof(double), typeof(int) });
                        if (setDevicePos != null)
                        {
                            setDevicePos.Invoke(null, new object[] { win, screenPt.X, screenPt.Y, 0.0, 0.0, 0 });
                            return false; // Handled! Do not fall back to stale WindowSettings.ApplyTo!
                        }
                    }

                    var source = PresentationSource.FromVisual(win);
                    if (source != null && source.CompositionTarget != null)
                    {
                        Point logicalPt = source.CompositionTarget.TransformFromDevice.Transform(screenPt);
                        win.Left = logicalPt.X;
                        win.Top = logicalPt.Y;
                        return false;
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.Error("[NativePortal] SubToolPanel_SetPosition_Prefix error: " + ex.Message);
            }
            return true;
        }

        public static bool PinnableWindow_RestoreLastPosition_Prefix(object __instance)
        {
            if (__instance != null && __instance.GetType().Name == "SubToolPanel")
            {
                // Prevent restoring stale/bad coordinates from Window.xml on startup
                return false;
            }
            return true;
        }

        public static void Popup_OnOpened_Postfix(Popup __instance)
        {
            if (__instance == null) return;
            try
            {
                lock (_openPopups)
                {
                    _openPopups.Add(new WeakReference(__instance));
                }
            }
            catch { }
        }

        public static void Popup_OnClosed_Postfix(Popup __instance)
        {
            if (__instance == null) return;
            try
            {
                lock (_openPopups)
                {
                    _openPopups.RemoveAll(wr => {
                        var target = wr.Target as Popup;
                        return target == null || target == __instance;
                    });
                }
            }
            catch { }
        }

        public static void CloseAllPopups()
        {
            try
            {
                lock (_openPopups)
                {
                    foreach (var wr in _openPopups.ToArray())
                    {
                        var p = wr.Target as Popup;
                        if (p != null && p.IsOpen)
                        {
                            p.IsOpen = false;
                        }
                    }
                    _openPopups.Clear();
                }
            }
            catch { }
        }

        public static void RepositionFloatingPanels()
        {
            try
            {
                var pinMgrType = AccessTools.TypeByName("Serif.Affinity.UI.Pinning.PinningManager");
                if (pinMgrType != null)
                {
                    var prop = AccessTools.Property(pinMgrType, "Instance");
                    var inst = prop != null ? prop.GetValue(null, null) : null;
                    if (inst != null)
                    {
                        var updateMethod = AccessTools.Method(pinMgrType, "UpdatePositions");
                        if (updateMethod != null)
                        {
                            updateMethod.Invoke(inst, null);
                        }
                    }
                }
            }
            catch { }
        }

        public override void OnUiReady(IPluginContext context)
        {
            Logger.Info("[NativePortal] OnUiReady! QueueFile=" + QUEUE_FILE);
            InitOnce();
        }

        public override void OnStartupComplete(IPluginContext context)
        {
            Logger.Info("[NativePortal] OnStartupComplete!");
            InitOnce();
        }

        private static void InitOnce()
        {
            if (_initialized) return;
            _initialized = true;
            StartQueueWatcher();

            var disp = Application.Current != null ? Application.Current.Dispatcher : Dispatcher.CurrentDispatcher;
            disp.BeginInvoke(DispatcherPriority.ApplicationIdle, new Action(() => {
                try {
                    AttachWindowListeners();
                    OpenFromQueueAndArgs();
                }
                catch (Exception ex) { Logger.Error("[NativePortal] Init error: " + ex); }
            }));
        }

        private static void AttachWindowListeners()
        {
            if (Application.Current == null || Application.Current.MainWindow == null) return;
            var win = Application.Current.MainWindow;

            win.LocationChanged += (s, e) => {
                RepositionFloatingPanels();
                CloseAllPopups();
            };
            win.SizeChanged += (s, e) => {
                RepositionFloatingPanels();
                CloseAllPopups();
            };
            win.Deactivated += (s, e) => CloseAllPopups();
            win.PreviewMouseDown += (s, e) => CloseAllPopups();
            Logger.Info("[NativePortal] Attached popup dismissal & panel reposition listeners to MainWindow.");
        }

        private static List<string> ReadAndClearQueue()
        {
            List<string> paths = new List<string>();
            try
            {
                if (!File.Exists(QUEUE_FILE))
                    return paths;
                string content = File.ReadAllText(QUEUE_FILE);
                try { File.Delete(QUEUE_FILE); } catch { }
                foreach (string line in content.Split(new char[]{'\r','\n'}, StringSplitOptions.RemoveEmptyEntries))
                {
                    string p = line.Trim().Trim('"', '\'');
                    if (string.IsNullOrEmpty(p) || paths.Contains(p)) continue;
                    if (!File.Exists(p)) continue;
                    paths.Add(p);
                }
            }
            catch (Exception ex) { Logger.Error("[NativePortal] ReadQueue error: " + ex.Message); }
            return paths;
        }

        private static void OpenFromQueueAndArgs()
        {
            List<string> paths = ReadAndClearQueue();
            string[] args = Environment.GetCommandLineArgs();
            for (int i = 1; i < args.Length; i++)
            {
                string p = args[i].Trim('"', '\'');
                if (string.IsNullOrEmpty(p) || paths.Contains(p)) continue;
                if (File.Exists(p)) paths.Add(p);
            }

            if (paths.Count > 0)
            {
                Logger.Info("[NativePortal] Startup opening " + paths.Count + " files: " + string.Join(", ", paths.ToArray()));
                CallOpenFiles(paths);
            }
        }

        private static void StartQueueWatcher()
        {
            if (_queueWatcherStarted) return;
            _queueWatcherStarted = true;
            var t = new Thread(() => {
                while (true)
                {
                    try
                    {
                        if (File.Exists(QUEUE_FILE) && Application.Current != null)
                        {
                            List<string> paths = ReadAndClearQueue();
                            if (paths.Count > 0)
                            {
                                List<string> cap = paths;
                                Application.Current.Dispatcher.BeginInvoke(DispatcherPriority.Normal, new Action(() => {
                                    CallOpenFiles(cap);
                                }));
                            }
                        }
                    }
                    catch { }
                    Thread.Sleep(100);
                }
            });
            t.IsBackground = true;
            t.Name = "NativePortalQueueWatcher";
            t.Start();
        }

        private static void CallOpenFiles(List<string> paths)
        {
            object app = Application.Current;
            if (app == null) return;
            Type cursor = app.GetType();
            while (cursor != null && cursor != typeof(object))
            {
                foreach (MethodInfo m in cursor.GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly))
                {
                    if (m.Name == "ProcessCommandLineArguments")
                    {
                        var ps = m.GetParameters();
                        if (ps.Length == 1 && ps[0].ParameterType != typeof(string[]))
                        {
                            try { m.Invoke(app, new object[] { paths }); return; } catch { }
                        }
                    }
                }
                cursor = cursor.BaseType;
            }
        }

        public static bool RunDialog_Prefix(FileDialog __instance, IntPtr hwndOwner, ref bool __result)
        {
            try
            {
                bool isSave = (__instance is SaveFileDialog);
                string mode = isSave ? "save" : "open";
                string scriptPath = "/home/ters/.affinity/native_file_chooser.sh";
                string outputFile = @"Z:\tmp\affinity_selected.txt";
                string doneFile = @"Z:\tmp\affinity_done.txt";

                try { if (File.Exists(outputFile)) File.Delete(outputFile); } catch { }
                try { if (File.Exists(doneFile)) File.Delete(doneFile); } catch { }

                string initDir = "";
                try { if (!string.IsNullOrEmpty(__instance.InitialDirectory)) initDir = __instance.InitialDirectory; } catch { }
                if (string.IsNullOrEmpty(initDir))
                    try { if (!string.IsNullOrEmpty(__instance.FileName)) initDir = Path.GetDirectoryName(__instance.FileName); } catch { }

                if (!string.IsNullOrEmpty(initDir))
                {
                    if (initDir.StartsWith("Z:\\", StringComparison.OrdinalIgnoreCase))
                        initDir = initDir.Substring(2).Replace('\\', '/');
                    else if (initDir.StartsWith("C:\\", StringComparison.OrdinalIgnoreCase))
                        initDir = "/home/ters/.affinity/drive_c/" + initDir.Substring(3).Replace('\\', '/');
                }

                var p = new Process();
                p.StartInfo.FileName = "start.exe";
                string args2 = "/unix /bin/bash " + scriptPath + " " + mode;
                if (!string.IsNullOrEmpty(initDir)) args2 += " \"" + initDir + "\"";
                p.StartInfo.Arguments = args2;
                p.StartInfo.UseShellExecute = false;
                p.StartInfo.CreateNoWindow = true;
                p.Start();

                int waited = 0;
                while (!File.Exists(doneFile) && waited < 600000) { Thread.Sleep(50); waited += 50; }
                try { if (File.Exists(doneFile)) File.Delete(doneFile); } catch { }

                if (File.Exists(outputFile))
                {
                    string lp = File.ReadAllText(outputFile).Trim();
                    try { File.Delete(outputFile); } catch { }
                    if (!string.IsNullOrEmpty(lp))
                    {
                        string wp = lp.StartsWith("/") ? @"Z:" + lp.Replace('/', '\\') : lp;
                        if (isSave && !string.IsNullOrEmpty(__instance.DefaultExt) && string.IsNullOrEmpty(Path.GetExtension(wp)))
                        {
                            string ext = __instance.DefaultExt;
                            if (!ext.StartsWith(".")) ext = "." + ext;
                            wp += ext;
                        }
                        __instance.FileName = wp;
                        __result = true;
                        return false;
                    }
                }
                __result = false;
                return false;
            }
            catch { return true; }
        }
    }
}

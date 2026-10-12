#ifndef GOOD_DAY_REGION_GLASS_H_
#define GOOD_DAY_REGION_GLASS_H_
#include <memory>
#include <windows.h>

// A visual-layer backdrop behind the Flutter child, rather than a backdrop
// across the entire HWND rectangle. Empty space has no visual at all.
class RegionGlass {
public:
  explicit RegionGlass(HWND window);
  ~RegionGlass();
  bool Update(double scale, bool notes, int selected, int count);
  void Hide();

private:
  struct State;
  std::unique_ptr<State> state_;
};
#endif

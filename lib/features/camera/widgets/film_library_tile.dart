import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/widgets/workspace_motion.dart';

class FilmLibraryTile extends StatelessWidget {
  const FilmLibraryTile(
      {required this.name,
      required this.available,
      required this.image,
      required this.onTap,
      super.key});
  final String name;
  final bool available;
  final Widget image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: name,
        hint: available ? '查看胶卷详情与装卷' : '仅可预览',
        child: Tooltip(
            message: name,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(3),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: AnimatedOpacity(
                            duration: WorkspaceMotion.duration(context, 160),
                            opacity: available ? 1 : .48,
                            child: available
                                ? image
                                : ColorFiltered(
                                    colorFilter: const ColorFilter.matrix([
                                      .2126,
                                      .7152,
                                      .0722,
                                      0,
                                      0,
                                      .2126,
                                      .7152,
                                      .0722,
                                      0,
                                      0,
                                      .2126,
                                      .7152,
                                      .0722,
                                      0,
                                      0,
                                      0,
                                      0,
                                      0,
                                      1,
                                      0,
                                    ]),
                                    child: image),
                          ),
                        )),
                    const SizedBox(height: 9),
                    Text(name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: available
                                ? GRemoteColors.text
                                : GRemoteColors.muted)),
                  ]),
            )),
      );
}
